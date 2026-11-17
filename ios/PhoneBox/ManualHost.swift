import Foundation

/// Validation of an address the user types for a paired computer (Tailscale 100.x IP, MagicDNS name, LAN name).
/// The pinned certificate still decides who answers, so the address only has to be a plausible host.
enum ManualHost {
    enum Failure: Error, Equatable {
        case empty
        case malformed
        case publicAddress
    }

    static let maxPerComputer = 8
    private static let label = "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"

    /// Returns the normalised (trimmed, lowercase) host, or why it was refused. Ports, schemes and paths are refused:
    /// the port is the one learned at pairing.
    static func validate(_ input: String) -> Result<String, Failure> {
        let host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return .failure(.empty) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard host.count <= 253, labels.allSatisfy({ $0.range(of: label, options: .regularExpression) != nil }) else {
            return .failure(.malformed)
        }
        // dotted digits are an IPv4 literal: only private and Tailscale ranges are accepted, as in the QR link
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return PairLink.isLocalAddress(host) ? .success(host) : .failure(.publicAddress)
        }
        return .success(host)
    }

    static func message(for failure: Failure) -> String {
        switch failure {
        case .empty: return "Nhập địa chỉ IP hoặc tên máy."
        case .malformed: return "Địa chỉ không hợp lệ. Chỉ nhập IP hoặc tên máy, không kèm http://, cổng hay đường dẫn."
        case .publicAddress: return "Chỉ chấp nhận địa chỉ mạng nội bộ hoặc Tailscale (100.64.x.x - 100.127.x.x)."
        }
    }
}
