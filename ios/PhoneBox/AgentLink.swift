import Foundation
import os

enum AgentRoute: String, Sendable { case wifi, none }

enum AgentLinkError: Error, Equatable {
    case offline
    case http(Int)
}

/// Connection to the PhoneBox agent over pinned HTTPS (Wi-Fi / Tailscale). Port of the Wi-Fi half of Android `AgentLink`.
actor AgentLink: AgentProxy {
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "link")
    private static let unknownPostResult = #"{"ok":false,"error":"The command result is unknown; check the computer before retrying"}"#

    private struct Sessions {
        let pin: String
        let forward: URLSession
        let stream: URLSession
    }

    private let store: PairedComputerStore
    private let identity: DeviceIdentity
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    private var state: PairedState
    private var sessions: Sessions?
    private var preferredHost = 0
    private(set) var route: AgentRoute = .none

    init(store: PairedComputerStore = PairedComputerStore(), identity: DeviceIdentity,
         makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.store = store
        self.identity = identity
        self.makeConfiguration = makeConfiguration
        self.state = store.load()
    }

    // MARK: paired computers

    var computers: PairedState { state }

    func upsert(_ pc: PairedComputer) throws { try update { $0.upsert(pc) } }
    func select(_ id: String) throws { try update { $0.select(id) } }
    func forget(_ id: String) throws { try update { $0.forget(id) } }
    func addExtraHost(_ host: String, to id: String) throws { try update { $0.addExtraHost(host, to: id) } }
    func removeExtraHost(_ host: String, from id: String) throws { try update { $0.removeExtraHost(host, from: id) } }

    private func update(_ change: (inout PairedState) -> Void) throws {
        var next = state
        change(&next)
        try store.save(next)
        state = next
        sessions?.forward.invalidateAndCancel()
        sessions?.stream.invalidateAndCancel()
        sessions = nil
        preferredHost = 0
    }

    // MARK: requests

    /// Forwards a request to the active computer. Never throws: failures become the same synthetic replies Android sends.
    func forward(method: String, pathAndQuery: String) async -> AgentReply {
        guard let pc = state.active, !pc.allHosts.isEmpty else { return offline() }
        let isPost = method == "POST"
        let session = pinnedSessions(for: pc).forward
        let hosts = pc.allHosts
        for index in hostOrder(hosts) {
            guard let request = makeRequest(pc, host: hosts[index], pathAndQuery: pathAndQuery,
                                            method: method, timeout: isPost ? 30 : 4) else { continue }
            do {
                let (body, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                preferredHost = index
                route = .wifi
                return AgentReply(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), body: body)
            } catch {
                Self.log.info("host \(index) failed: \(String(describing: error), privacy: .public)")
                // A POST may already have reached the agent: running it on another address could act twice.
                if isPost && !Self.requestNeverSent(error) {
                    route = .none
                    return .json(504, Self.unknownPostResult)
                }
            }
        }
        return offline()
    }

    /// Opens the live stream (GET /api/stream) and returns its lines, blank ones included.
    func openStream() async throws -> AsyncThrowingStream<String, Error> {
        guard let pc = state.active, !pc.allHosts.isEmpty else { throw AgentLinkError.offline }
        let session = pinnedSessions(for: pc).stream
        let hosts = pc.allHosts
        for index in hostOrder(hosts) {
            guard let request = makeRequest(pc, host: hosts[index], pathAndQuery: "/api/stream", method: "GET", timeout: 8) else { continue }
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard http.statusCode == 200 else { throw AgentLinkError.http(http.statusCode) }
                preferredHost = index
                route = .wifi
                return Self.lines(of: bytes)
            } catch let error as AgentLinkError {
                throw error
            } catch {
                Self.log.info("stream host \(index) failed: \(String(describing: error), privacy: .public)")
            }
        }
        route = .none
        throw AgentLinkError.offline
    }

    // MARK: helpers

    private func offline() -> AgentReply {
        route = .none
        return .json(503, #"{"error":"offline"}"#)
    }

    /// Last good address first, then the rest in the paired order.
    private func hostOrder(_ hosts: [String]) -> [Int] {
        hosts.indices.sorted { ($0 == preferredHost ? -1 : $0) < ($1 == preferredHost ? -1 : $1) }
    }

    private func pinnedSessions(for pc: PairedComputer) -> Sessions {
        if let sessions, sessions.pin == pc.id { return sessions }
        sessions?.forward.invalidateAndCancel()
        sessions?.stream.invalidateAndCancel()
        let delegate = PinnedTrustDelegate(pin: pc.id)
        let forward = makeConfiguration()
        let stream = makeConfiguration()
        for c in [forward, stream] {
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            c.urlCache = nil
            c.httpShouldSetCookies = false
            c.httpCookieStorage = nil
        }
        stream.timeoutIntervalForRequest = 8 // the agent sends "state" every second, so silence this long is a dead link
        let next = Sessions(pin: pc.id, forward: URLSession(configuration: forward, delegate: delegate, delegateQueue: nil),
                            stream: URLSession(configuration: stream, delegate: delegate, delegateQueue: nil))
        sessions = next
        return next
    }

    private func makeRequest(_ pc: PairedComputer, host: String, pathAndQuery: String, method: String, timeout: TimeInterval) -> URLRequest? {
        guard let url = URL(string: "https://\(host):\(pc.port)\(pathAndQuery)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(pc.token)", forHTTPHeaderField: "Authorization")
        request.setValue(identity.appVersion, forHTTPHeaderField: "X-PhoneBox-App")
        request.setValue(identity.deviceId, forHTTPHeaderField: "X-PhoneBox-Device")
        request.setValue(identity.model, forHTTPHeaderField: "X-PhoneBox-Model")
        if method == "POST" { request.httpBody = Data() }
        return request
    }

    /// Errors that prove no request bytes were sent, so another address is safe to try for a POST.
    private static func requestNeverSent(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
                .secureConnectionFailed, .serverCertificateUntrusted, .cancelled].contains(code)
    }

    private static func lines(of bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var splitter = LineSplitter()
                    for try await byte in bytes {
                        if let line = splitter.push(byte) { continuation.yield(line) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
