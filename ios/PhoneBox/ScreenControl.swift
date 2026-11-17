import os
import UIKit

extension OrientationMode {
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .landscape: return .landscape
        case .portrait: return .portrait
        case .auto: return .allButUpsideDown
        }
    }
}

protocol BrightnessScreen: AnyObject {
    var brightness: CGFloat { get set }
}

extension UIScreen: BrightnessScreen {}

/// Panel-requested screen brightness. iOS brightness is system-wide, so the user's own level is saved on the first
/// change and handed back whenever the panel stops controlling it or the app leaves the screen.
@MainActor
final class BrightnessController {
    static let minimum = 0.01

    private let screen: @MainActor () -> (any BrightnessScreen)?
    private var original: CGFloat?
    private(set) var desired: Double?

    init(screen: @escaping @MainActor () -> (any BrightnessScreen)? = BrightnessController.foregroundScreen) {
        self.screen = screen
    }

    /// 0...1, or a negative value to return control to the system setting.
    func request(_ value: Double) {
        if value < 0 {
            desired = nil
            restore()
        } else {
            desired = max(value, Self.minimum)
            apply()
        }
    }

    /// App inactive or backgrounded: give the user's brightness back but remember what the panel wanted.
    func suspend() { restore() }

    func resume() { apply() }

    private func apply() {
        guard let desired, let screen = screen() else { return }
        if original == nil { original = screen.brightness }
        screen.brightness = CGFloat(desired)
    }

    private func restore() {
        guard let original, let screen = screen() else { return }
        screen.brightness = original
        self.original = nil
    }

    static func foregroundScreen() -> (any BrightnessScreen)? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }
}

/// Applies the panel's orientation choice. `OrientationLock.mask` feeds the app delegate; the scene is then asked to
/// rotate into it.
@MainActor
final class OrientationController {
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "orientation")
    private let refresh: (UIInterfaceOrientationMask) -> Void

    init(refresh: @escaping (UIInterfaceOrientationMask) -> Void = OrientationController.updateScenes) {
        self.refresh = refresh
    }

    func set(_ mode: OrientationMode) {
        guard OrientationLock.mask != mode.mask else { return }
        OrientationLock.mask = mode.mask
        refresh(mode.mask)
    }

    static func updateScenes(_ mask: UIInterfaceOrientationMask) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                log.error("orientation change refused: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
