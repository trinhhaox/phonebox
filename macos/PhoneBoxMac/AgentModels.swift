import Foundation

/// GET /api/info. Only the fields the menu needs; the agent adds more over time and unknown keys are ignored.
struct AgentInfo: Decodable, Equatable {
    let version: String
    let connected: Bool
    /// "USB" or "Wi-Fi" when a phone is connected.
    let via: String?
    let devices: [String]
    let appMissing: [String]

    init(version: String, connected: Bool, via: String?, devices: [String] = [], appMissing: [String] = []) {
        self.version = version
        self.connected = connected
        self.via = via
        self.devices = devices
        self.appMissing = appMissing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        connected = try c.decode(Bool.self, forKey: .connected)
        via = try c.decodeIfPresent(String.self, forKey: .via)
        devices = try c.decodeIfPresent([String].self, forKey: .devices) ?? []
        appMissing = try c.decodeIfPresent([String].self, forKey: .appMissing) ?? []
    }

    private enum CodingKeys: String, CodingKey { case version, connected, via, devices, appMissing }
}

/// One entry of GET /api/phones: a phone that has talked to the agent (lastSeen is Unix milliseconds).
struct PhoneRecord: Decodable, Equatable, Identifiable {
    let id: String
    let model: String?
    let name: String?
    let via: String?
    let lastSeen: Double?

    /// The user's own label wins over the model reported by the phone.
    var displayName: String {
        for candidate in [name, model] {
            if let text = candidate?.trimmingCharacters(in: .whitespaces), !text.isEmpty { return text }
        }
        return "Điện thoại \(id.prefix(6))"
    }

    func isRecent(now: Date = Date(), window: TimeInterval = AgentMonitorTiming.phoneRecentWindow) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince1970 - lastSeen / 1000 <= window
    }
}

enum AgentMonitorTiming {
    /// A phone counts as "connected" in the list when it talked to the agent within this many seconds.
    static let phoneRecentWindow: TimeInterval = 30
}
