import AppKit
import Combine
import SwiftUI

/// Creates and tracks the app windows. A window's web view is torn down when the window closes,
/// so a closed panel does not keep streaming in the background.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let panelAutosaveName = "PhoneBoxPanelWindow"
    static let settingsAutosaveName = "PhoneBoxSettingsWindow"
    static let panelDefaultSize = NSSize(width: 900, height: 420)
    static let settingsDefaultSize = NSSize(width: 1000, height: 720)

    let preferences: PanelPreferences
    let monitor: AgentMonitor
    private var panelWindow: NSWindow?
    private var panelModel: SecureWebViewModel?
    private var settingsWindow: NSWindow?
    private var settingsModel: SecureWebViewModel?
    private var installerWindow: NSWindow?
    private var installerModel: InstallerModel?
    private var preferenceSubscriptions = Set<AnyCancellable>()

    init(preferences: PanelPreferences, monitor: AgentMonitor) {
        self.preferences = preferences
        self.monitor = monitor
        super.init()
    }

    func showPanel() {
        if let panelWindow { bringToFront(panelWindow); return }
        let model = SecureWebViewModel(url: AgentEndpoint.panelURL)
        let host = NSHostingController(rootView: PanelRootView(model: model, preferences: preferences))
        let window = makeWindow(title: "PhoneBox", content: host, size: Self.panelDefaultSize,
                                autosave: Self.panelAutosaveName, minSize: NSSize(width: 480, height: 240))
        panelModel = model
        panelWindow = window
        applyPanelPreferences(to: window)
        preferences.$alwaysOnTop.combineLatest(preferences.$opacity)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.applyPanelPreferences(to: window)
            }
            .store(in: &preferenceSubscriptions)
        bringToFront(window)
    }

    func showSettings(pairing: Bool = false) {
        if let settingsWindow {
            bringToFront(settingsWindow)
            if pairing { settingsModel?.openPairingDialog() }
            return
        }
        let model = SecureWebViewModel(url: AgentEndpoint.settingsURL)
        let rootView = SettingsRootView(model: model, monitor: monitor) { [weak self] in
            guard let self else { return }
            self.monitor.quitCompletely(windows: self)
        }
        let window = makeWindow(title: "Cài đặt PhoneBox", content: NSHostingController(rootView: rootView),
                                size: Self.settingsDefaultSize, autosave: Self.settingsAutosaveName,
                                minSize: NSSize(width: 640, height: 420))
        settingsModel = model
        settingsWindow = window
        if pairing { model.openPairingDialog() }
        bringToFront(window)
    }

    /// Installer log window; `onSuccess` runs after setup.sh exits cleanly (the menu refreshes the agent status).
    func showInstaller(onSuccess: @escaping () -> Void) {
        if let installerWindow { bringToFront(installerWindow); return }
        let model = InstallerModel(onSuccess: onSuccess)
        let window = makeWindow(title: "Cài đặt PhoneBox agent", content: NSHostingController(rootView: InstallerView(model: model)),
                                size: NSSize(width: 600, height: 380), autosave: "PhoneBoxInstallerWindow",
                                minSize: NSSize(width: 520, height: 320))
        installerModel = model
        installerWindow = window
        bringToFront(window)
        model.start()
    }

    func closeAll() {
        panelWindow?.close()
        settingsWindow?.close()
        installerWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === panelWindow {
            panelWindow = nil
            panelModel = nil
            preferenceSubscriptions.removeAll()
        } else if window === installerWindow {
            installerModel?.cancel()
            installerWindow = nil
            installerModel = nil
        } else if window === settingsWindow {
            settingsWindow = nil
            settingsModel = nil
        }
    }

    private func makeWindow(title: String, content: NSViewController, size: NSSize, autosave: String, minSize: NSSize) -> NSWindow {
        let window = NSWindow(contentViewController: content)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.delegate = self
        window.setContentSize(size)
        window.center()
        // Restores the saved frame when there is one; otherwise the size and position above stay.
        window.setFrameAutosaveName(autosave)
        return window
    }

    private func applyPanelPreferences(to window: NSWindow) {
        window.level = preferences.alwaysOnTop ? .floating : .normal
        window.alphaValue = CGFloat(preferences.opacity)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
