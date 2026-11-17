import UIKit

/// Orientations the app may rotate to. Landscape by default (desk panel); the bridge can change it later.
enum OrientationLock {
    nonisolated(unsafe) static var mask: UIInterfaceOrientationMask = .landscape
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
