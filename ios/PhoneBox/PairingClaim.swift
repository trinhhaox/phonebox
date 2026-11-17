import Foundation
import os

enum PairingError: Error, Equatable {
    case codeRejected(pc: String)
    case differentCertificate(host: String)
    case mismatchedReply(pc: String)
    case unreachable(pc: String, hosts: [String], status: Int?)

    /// User-facing text (Vietnamese).
    var message: String {
        switch self {
        case .codeRejected(let pc):
            return "\(pc) không nhận mã: mã chỉ dùng một lần và trong 5 phút. Hãy bắt đầu ghép nối lại trên máy tính."
        case .differentCertificate(let host):
            return "Máy tính tại \(host) dùng chứng chỉ khác với mã QR. Hãy bắt đầu ghép nối lại."
        case .mismatchedReply(let pc):
            return "\(pc) gửi chứng chỉ khác. Hãy bắt đầu ghép nối lại."
        case .unreachable(let pc, let hosts, let status):
            let detail = status.map { " Máy trả về mã \($0)." } ?? ""
            return "Không kết nối được \(pc) tại \(hosts.joined(separator: ", ")).\(detail) Điện thoại và máy tính phải cùng mạng " +
                "(hoặc cùng Tailscale), cho phép PhoneBox truy cập mạng cục bộ và tường lửa của máy tính phải cho phép."
        }
    }
}

/// Trades a pairing link's one-time code for the Wi-Fi key (POST /api/pair/claim), pinned to the QR fingerprint.
/// Port of Android `AgentLink.claim`. Does not touch the store: the caller saves the returned computer.
struct PairingClaim: Sendable {
    private struct Reply: Decodable {
        let fingerprint: String
        let token: String
        let port: Int?
        let hosts: [String]?
    }

    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "pairing")
    /// What the pin delegate does to a certificate it rejects shows up as one of these.
    private static let certificateFailures: Set<URLError.Code> = [
        .cancelled, .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
    ]

    let model: String
    let makeConfiguration: @Sendable () -> URLSessionConfiguration

    init(model: String, makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.model = model
        self.makeConfiguration = makeConfiguration
    }

    func claim(_ link: PairLink) async -> Result<PairedComputer, PairingError> {
        let configuration = makeConfiguration()
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: PinnedTrustDelegate(pin: link.fingerprint), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var lastStatus: Int?
        var certificateHost: String?
        for host in link.hosts {
            guard let request = makeRequest(link, host: host) else { continue }
            do {
                let (body, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                switch http.statusCode {
                case 200: break
                case 403: return .failure(.codeRejected(pc: link.pc))
                default: lastStatus = http.statusCode; continue
                }
                guard let reply = try? JSONDecoder().decode(Reply.self, from: body), !reply.token.isEmpty else { continue }
                guard reply.fingerprint.lowercased() == link.fingerprint else { return .failure(.mismatchedReply(pc: link.pc)) }
                return .success(computer(link, reply))
            } catch {
                Self.log.info("claim via \(host, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                if let code = (error as? URLError)?.code, Self.certificateFailures.contains(code) { certificateHost = host }
            }
        }
        if let certificateHost { return .failure(.differentCertificate(host: certificateHost)) }
        return .failure(.unreachable(pc: link.pc, hosts: link.hosts, status: lastStatus))
    }

    private func computer(_ link: PairLink, _ reply: Reply) -> PairedComputer {
        let offered = (reply.hosts ?? []).filter(PairLink.isLocalAddress)
        // only an entry for this very certificate is replaced later, never one that merely has the same name
        return PairedComputer(id: link.fingerprint, name: link.pc, hosts: offered.isEmpty ? link.hosts : offered,
                              port: reply.port.flatMap { (1...65535).contains($0) ? $0 : nil } ?? link.port, token: reply.token)
    }

    private func makeRequest(_ link: PairLink, host: String) -> URLRequest? {
        guard let url = URL(string: "https://\(host):\(link.port)/api/pair/claim"),
              let body = try? JSONEncoder().encode(["code": link.code]) else { return nil }
        // URLSession has no separate connect timeout: 8 s covers Android's 3 s connect + 8 s read in practice
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(model, forHTTPHeaderField: "X-PhoneBox-Model")
        return request
    }
}
