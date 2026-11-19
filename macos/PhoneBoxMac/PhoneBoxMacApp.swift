import SwiftUI

/// Shared objects for the menu and the windows; the agent poll starts at launch, not when the menu is first opened.
@MainActor
final class AppServices {
    static let shared = AppServices()
    let monitor = AgentMonitor()
    let launchAtLogin = LaunchAtLogin()
    let preferences = PanelPreferences()
    let windows: WindowCoordinator

    private init() { windows = WindowCoordinator(preferences: preferences, monitor: monitor) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            AppServices.shared.monitor.start(autoBootstrap: !isRunningTests)
            // `open PhoneBox.app --args --show-panel` opens the panel straight away (scripting and screenshots).
            if CommandLine.arguments.contains("--show-panel") { AppServices.shared.windows.showPanel() }
        }
    }
}

@main
struct PhoneBoxMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var monitor = AppServices.shared.monitor

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, launchAtLogin: AppServices.shared.launchAtLogin,
                        preferences: AppServices.shared.preferences, windows: AppServices.shared.windows)
        } label: {
            Image(systemName: symbol)
        }
        .menuBarExtraStyle(.menu)
    }

    private var symbol: String {
        switch monitor.status {
        case let .running(info): return info.connected ? "iphone.radiowaves.left.and.right" : "iphone"
        case .checking: return "iphone"
        case .stopped, .notInstalled: return "iphone.slash"
        }
    }
}
