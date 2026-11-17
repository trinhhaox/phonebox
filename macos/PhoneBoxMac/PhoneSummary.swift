import Foundation

/// Turns /api/info + /api/phones into the lines the menu shows under "Điện thoại".
enum PhoneSummary {
    static func lines(info: AgentInfo, phones: [PhoneRecord], now: Date = Date()) -> [String] {
        let recent = phones.filter { $0.isRecent(now: now) }
        if !recent.isEmpty {
            return recent.map { "\($0.displayName) · \(Self.transport($0.via ?? info.via))" }
        }
        if info.connected { return ["Điện thoại · \(Self.transport(info.via))"] }
        return []
    }

    private static func transport(_ via: String?) -> String {
        switch via {
        case "USB": return "USB"
        case "Wi-Fi": return "Wi-Fi"
        default: return "đã kết nối"
        }
    }
}
