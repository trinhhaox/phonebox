import Foundation
import os

/// A computer this phone is paired with; the certificate fingerprint (lowercase hex SHA-256) is its id.
struct PairedComputer: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let hosts: [String]
    let port: Int
    let token: String
    /// Addresses typed by the user (Tailscale IP, MagicDNS name). Kept apart from `hosts` so re-pairing never drops them.
    var extraHosts: [String]

    init(id: String, name: String, hosts: [String], port: Int, token: String, extraHosts: [String] = []) {
        self.id = id
        self.name = name
        self.hosts = hosts
        self.port = port
        self.token = token
        self.extraHosts = extraHosts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hosts = try c.decode([String].self, forKey: .hosts)
        port = try c.decode(Int.self, forKey: .port)
        token = try c.decode(String.self, forKey: .token)
        extraHosts = try c.decodeIfPresent([String].self, forKey: .extraHosts) ?? [] // state saved before manual addresses existed
    }

    /// Every address to try: the paired ones first, then the manual ones, without duplicates.
    var allHosts: [String] {
        var seen = Set<String>()
        return (hosts + extraHosts).filter { seen.insert($0).inserted }
    }
}

/// The paired computers and which one is used. Pure value: all list rules live here so they are testable.
struct PairedState: Codable, Equatable, Sendable {
    var computers: [PairedComputer] = []
    var activeId: String?

    /// The active computer, or the first one when the active id is gone.
    var active: PairedComputer? { computers.first { $0.id == activeId } ?? computers.first }

    /// Adds or replaces the entry for the same certificate and makes it active.
    mutating func upsert(_ pc: PairedComputer) {
        var pc = pc
        if pc.extraHosts.isEmpty, let old = computers.first(where: { $0.id == pc.id }) { pc.extraHosts = old.extraHosts }
        computers = computers.filter { $0.id != pc.id } + [pc]
        activeId = pc.id
    }

    @discardableResult
    mutating func select(_ id: String) -> Bool {
        guard computers.contains(where: { $0.id == id }) else { return false }
        activeId = id
        return true
    }

    /// Adds a manual address to one computer; false when the computer is unknown. Duplicates are ignored.
    @discardableResult
    mutating func addExtraHost(_ host: String, to id: String) -> Bool {
        guard let i = computers.firstIndex(where: { $0.id == id }) else { return false }
        if !computers[i].allHosts.contains(host) { computers[i].extraHosts.append(host) }
        return true
    }

    mutating func removeExtraHost(_ host: String, from id: String) {
        guard let i = computers.firstIndex(where: { $0.id == id }) else { return }
        computers[i].extraHosts.removeAll { $0 == host }
    }

    mutating func forget(_ id: String) {
        computers.removeAll { $0.id == id }
        if activeId == id { activeId = computers.first?.id }
    }
}

/// Persists [PairedState] as one JSON item in the Keychain (it holds the Wi-Fi tokens).
struct PairedComputerStore: Sendable {
    private static let key = "state"
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "pairing")
    let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) { self.keychain = keychain }

    /// Empty state when nothing is stored, the item is unreadable, or the JSON is corrupt (the phone then needs pairing again).
    func load() -> PairedState {
        do {
            guard let data = try keychain.read(Self.key) else { return PairedState() }
            return try JSONDecoder().decode(PairedState.self, from: data)
        } catch {
            Self.log.error("pairing state unreadable, starting empty: \(String(describing: error), privacy: .public)")
            return PairedState()
        }
    }

    func save(_ state: PairedState) throws {
        try keychain.write(Self.key, try JSONEncoder().encode(state))
    }
}
