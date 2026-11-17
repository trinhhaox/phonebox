import UIKit

/// Same JSON shape as Android's `battery()` minus the fields iOS does not expose (temperature, charger type, USB link).
struct BatterySnapshot: Codable, Equatable {
    var level: Int
    var plugged: Bool
    var temp: Double
    var source: String
}

enum DeviceInfo {
    /// `level` is UIDevice.batteryLevel (0...1, -1 unknown); a charging or full battery counts as plugged in.
    static func battery(level: Float, state: UIDevice.BatteryState) -> BatterySnapshot {
        BatterySnapshot(level: level < 0 ? -1 : Int((level * 100).rounded()),
                        plugged: state == .charging || state == .full, temp: 0, source: "")
    }

    @MainActor static func currentBattery() -> BatterySnapshot {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return battery(level: device.batteryLevel, state: device.batteryState)
    }

    /// The "j" template resolves to the phone's 12/24-hour choice; 12-hour patterns contain the am/pm marker "a".
    static func is24Hour(locale: Locale = .current) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return !format.contains("a")
    }

    static func version(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
