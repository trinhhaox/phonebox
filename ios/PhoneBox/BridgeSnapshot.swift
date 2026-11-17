import Foundation

struct BridgeComputer: Codable, Equatable {
    let id: String
    let name: String
    let active: Bool
}

struct BridgeSensors: Codable, Equatable {
    var light = false
    var proximity = false
}

/// What the shim's synchronous getters return. iOS has no light or proximity sensor the panel could use, so both are false.
struct BridgeSnapshot: Codable, Equatable {
    var battery: BatterySnapshot
    var transport: String
    var is24Hour: Bool
    var version: String
    var pcs: [BridgeComputer]
    var sensors = BridgeSensors()
    var canListen: Bool

    static func computers(_ state: PairedState) -> [BridgeComputer] {
        let active = state.active?.id
        return state.computers.map { BridgeComputer(id: $0.id, name: $0.name, active: $0.id == active) }
    }
}

/// Fields pushed to a running page; unset fields stay as the page has them.
struct BridgeUpdate: Encodable, Equatable {
    var battery: BatterySnapshot?
    var pcs: [BridgeComputer]?
}

enum BridgeScripts {
    /// The shim with its two placeholders filled in. The key is a UUID and the state is JSON, so neither can break out of the script.
    static func shim(template: String, key: String, snapshot: BridgeSnapshot) -> String? {
        guard let json = encode(snapshot) else { return nil }
        return template.replacingOccurrences(of: "__KEY__", with: key).replacingOccurrences(of: "__STATE__", with: json)
    }

    static func update(_ update: BridgeUpdate) -> String? {
        encode(update).map { "window.__pbNative && window.__pbNative.update(\($0))" }
    }

    static func speech(kind: String, text: String, id: Int) -> String {
        "window.onAndroidSpeech && window.onAndroidSpeech(\(JSQuote.string(kind)), \(JSQuote.string(text)), \(id))"
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return nil }
        return text.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
