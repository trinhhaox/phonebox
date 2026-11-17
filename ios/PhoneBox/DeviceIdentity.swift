import CryptoKit
import Foundation
import UIKit

/// What this phone tells the agent about itself (X-PhoneBox-Device / -Model / -App).
struct DeviceIdentity: Sendable {
    let deviceId: String
    let model: String
    let appVersion: String

    /// Short stable id: first 6 bytes of SHA-256 of the vendor id, as 12 hex characters.
    static func hashedId(from source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Printable ASCII only, at most 40 characters (header-safe).
    static func sanitizedModel(_ raw: String) -> String {
        String(String(raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value <= 0x7E }).trimmingCharacters(in: .whitespaces).prefix(40))
    }

    @MainActor
    static func current(bundle: Bundle = .main) -> DeviceIdentity {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let vendor = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let version = bundle.object(forInfoDictionaryKey: "PhoneBoxPanelVersion") as? String ?? ""
        return DeviceIdentity(deviceId: hashedId(from: vendor), model: sanitizedModel("Apple \(machine)"), appVersion: version)
    }
}
