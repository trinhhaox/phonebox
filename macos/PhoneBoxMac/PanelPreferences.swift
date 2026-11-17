import Foundation

/// Panel window options, remembered between launches.
@MainActor
final class PanelPreferences: ObservableObject {
    static let opacityRange: ClosedRange<Double> = 0.3...1.0

    private let defaults: UserDefaults

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    @Published var opacity: Double {
        didSet {
            let clamped = Self.clamp(opacity)
            if clamped != opacity { opacity = clamped; return }
            defaults.set(opacity, forKey: Keys.opacity)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        let stored = defaults.object(forKey: Keys.opacity) as? Double
        opacity = Self.clamp(stored ?? 1.0)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return opacityRange.upperBound }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    private enum Keys {
        static let alwaysOnTop = "panel.alwaysOnTop"
        static let opacity = "panel.opacity"
    }
}
