import XCTest
@testable import PhoneBox

private final class StubProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    nonisolated(unsafe) static var handler: Handler = { _ in (200, Data()) }
    nonisolated(unsafe) static var seen = [URLRequest]()
    private static let lock = NSLock()

    static func reset(_ h: @escaping Handler) { lock.lock(); handler = h; seen = []; lock.unlock() }
    static func hosts() -> [String] { lock.lock(); defer { lock.unlock() }; return seen.compactMap { $0.url?.host } }
    static func last() -> URLRequest? { lock.lock(); defer { lock.unlock() }; return seen.last }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.seen.append(request); let h = Self.handler; Self.lock.unlock()
        do {
            let (code, body) = try h(request)
            let r = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class AgentLinkTests: XCTestCase {
    private let pin = String(repeating: "ab", count: 32)
    private var keychain = KeychainStore(service: "phonebox.tests.\(UUID().uuidString)")

    override func tearDown() { try? keychain.delete("state") }

    private func makeLink(hosts: [String] = ["10.0.0.1", "10.0.0.2"], paired: Bool = true) throws -> AgentLink {
        let store = PairedComputerStore(keychain: keychain)
        if paired {
            var s = PairedState()
            s.upsert(PairedComputer(id: pin, name: "Mac", hosts: hosts, port: 8766, token: "tok"))
            try store.save(s)
        }
        let identity = DeviceIdentity(deviceId: "0123456789ab", model: "Apple iPhone15,2", appVersion: "0.9.16")
        return AgentLink(store: store, identity: identity) {
            let c = URLSessionConfiguration.ephemeral
            c.protocolClasses = [StubProtocol.self]
            return c
        }
    }

    func testSendsPinnedUrlAuthAndPhoneBoxHeaders() async throws {
        StubProtocol.reset { _ in (200, Data(#"{"ok":1}"#.utf8)) }
        let reply = try await makeLink().forward(method: "GET", pathAndQuery: "/api/state?x=1")
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.contentType, "application/json")
        let req = try XCTUnwrap(StubProtocol.last())
        XCTAssertEqual(req.url?.absoluteString, "https://10.0.0.1:8766/api/state?x=1")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-PhoneBox-App"), "0.9.16")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-PhoneBox-Device"), "0123456789ab")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-PhoneBox-Model"), "Apple iPhone15,2")
        XCTAssertNil(req.value(forHTTPHeaderField: "Origin"))
    }

    func testGetFallsBackToNextHostAndRemembersIt() async throws {
        StubProtocol.reset { r in
            if r.url?.host == "10.0.0.1" { throw URLError(.cannotConnectToHost) }
            return (200, Data())
        }
        let link = try makeLink()
        let first = await link.forward(method: "GET", pathAndQuery: "/a")
        XCTAssertEqual(first.status, 200)
        _ = await link.forward(method: "GET", pathAndQuery: "/b")
        XCTAssertEqual(StubProtocol.hosts(), ["10.0.0.1", "10.0.0.2", "10.0.0.2"])
    }

    func testAllHostsDownIs503Offline() async throws {
        StubProtocol.reset { _ in throw URLError(.timedOut) }
        let reply = try await makeLink().forward(method: "GET", pathAndQuery: "/a")
        XCTAssertEqual(reply.status, 503)
        XCTAssertEqual(String(data: reply.body, encoding: .utf8), #"{"error":"offline"}"#)
    }

    func testNotPairedIs503WithoutNetwork() async throws {
        StubProtocol.reset { _ in (200, Data()) }
        let reply = try await makeLink(paired: false).forward(method: "GET", pathAndQuery: "/a")
        XCTAssertEqual(reply.status, 503)
        XCTAssertTrue(StubProtocol.hosts().isEmpty)
    }

    func testPostAfterTimeoutIsNotRetriedOnAnotherHost() async throws {
        StubProtocol.reset { r in
            if r.url?.host == "10.0.0.1" { throw URLError(.timedOut) }
            return (200, Data())
        }
        let reply = try await makeLink().forward(method: "POST", pathAndQuery: "/api/macro")
        XCTAssertEqual(reply.status, 504)
        XCTAssertTrue(String(decoding: reply.body, as: UTF8.self).contains("unknown"))
        XCTAssertEqual(StubProtocol.hosts(), ["10.0.0.1"])
    }

    func testPostConnectRefusedMayTryNextHost() async throws {
        StubProtocol.reset { r in
            if r.url?.host == "10.0.0.1" { throw URLError(.cannotConnectToHost) }
            return (200, Data())
        }
        let reply = try await makeLink().forward(method: "POST", pathAndQuery: "/api/macro")
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(StubProtocol.last()?.httpMethod, "POST")
    }

    func testHttpErrorStatusIsPassedThrough() async throws {
        StubProtocol.reset { _ in (403, Data()) }
        let reply = try await makeLink().forward(method: "GET", pathAndQuery: "/api/settings")
        XCTAssertEqual(reply.status, 403)
    }

    func testForgetStopsTraffic() async throws {
        StubProtocol.reset { _ in (200, Data()) }
        let link = try makeLink()
        try await link.forget(pin)
        let reply = await link.forward(method: "GET", pathAndQuery: "/a")
        XCTAssertEqual(reply.status, 503)
    }
}
