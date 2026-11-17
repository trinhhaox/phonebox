import Foundation

/// What the pairing QR code (or the "Open in PhoneBox" button on the pair page) carries. Port of Android `AgentLink.PairLink`.
/// The code is a one-time secret: never log it.
struct PairLink: Equatable, Sendable {
    static let defaultComputerName = "your computer"
    private static let maxHosts = 8
    private static let fingerprintPattern = "^[0-9a-f]{64}$"
    private static let codePattern = "^[A-Za-z0-9_-]{16,64}$"

    let pc: String
    let fingerprint: String
    let port: Int
    let hosts: [String]
    let code: String

    /// First 8 hex digits of the fingerprint, as "ABCD 1234". The computer shows the same text next to its QR code,
    /// so a link from anywhere else shows a different one.
    var check: String {
        let head = Array(fingerprint.prefix(8).uppercased())
        return String(head.prefix(4)) + " " + String(head.dropFirst(4))
    }

    /// Private networks (10/8, 172.16/12, 192.168/16) and Tailscale (100.64/10), IPv4 only: the addresses the agent offers.
    static func isLocalAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var b = [Int]()
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(part), n <= 255 else { return false }
            b.append(n)
        }
        return b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
            || (b[0] == 100 && (64...127).contains(b[1]))
    }

    /// Reads `https://ersinkoc.github.io/phonebox/pair/#v=1&...` (data in the fragment) or `phonebox://pair?v=1&...`.
    /// Anything malformed returns nil.
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let raw: String?
        switch (parts.scheme?.lowercased(), parts.host?.lowercased()) {
        case ("https", "ersinkoc.github.io") where parts.path.hasPrefix("/phonebox/pair"): raw = parts.percentEncodedFragment
        case ("phonebox", "pair"): raw = parts.percentEncodedQuery
        default: raw = nil
        }
        guard let raw else { return nil }
        var q = [String: String]()
        for item in raw.split(separator: "&") {
            guard let eq = item.firstIndex(of: "="), eq != item.startIndex else { continue }
            q[String(item[..<eq])] = String(item[item.index(after: eq)...]).removingPercentEncoding ?? ""
        }
        guard q["v"] == "1",
              let fp = q["fp"]?.lowercased(), fp.range(of: Self.fingerprintPattern, options: .regularExpression) != nil,
              let port = q["port"].flatMap({ Int($0) }), (1...65535).contains(port),
              let code = q["c"], code.range(of: Self.codePattern, options: .regularExpression) != nil else { return nil }
        let hosts = (q["h"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(Self.isLocalAddress).prefix(Self.maxHosts)
        guard !hosts.isEmpty else { return nil }
        let name = String(String(q["pc"] ?? "").unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.prefix(64))
        self.init(pc: name.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultComputerName : name,
                  fingerprint: fp, port: port, hosts: Array(hosts), code: code)
    }

    init(pc: String, fingerprint: String, port: Int, hosts: [String], code: String) {
        self.pc = pc
        self.fingerprint = fingerprint
        self.port = port
        self.hosts = hosts
        self.code = code
    }
}
