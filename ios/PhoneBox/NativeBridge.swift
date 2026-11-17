import os
import UIKit
import WebKit

/// Receives the panel's `window.Android` calls (posted by bridge-shim.js), validates them and runs the native side.
/// Only the main frame of `pbapp://panel` holding this launch's key is obeyed.
@MainActor
final class NativeBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "phonebox"
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "bridge")

    let key: String
    private(set) var snapshot: BridgeSnapshot
    /// Runs a script in the panel's main frame (set by PanelView).
    var runScript: (String) -> Void = { _ in }
    /// Reloads the panel (after switching computer).
    var reloadPanel: () -> Void = {}

    private let computers: (any PairedComputerSource)?
    private let haptics: any HapticsPlaying
    private let brightness: BrightnessController
    private let orientation: OrientationController
    private let dictation: SpeechDictation
    private let shimTemplate: String?
    private weak var userContent: WKUserContentController?
    private var observers: [NSObjectProtocol] = []

    init(key: String = UUID().uuidString, computers: (any PairedComputerSource)?, haptics: any HapticsPlaying,
         brightness: BrightnessController, orientation: OrientationController, dictation: SpeechDictation,
         shimTemplate: String? = NativeBridge.bundledShim()) {
        self.key = key
        self.computers = computers
        self.haptics = haptics
        self.brightness = brightness
        self.orientation = orientation
        self.dictation = dictation
        self.shimTemplate = shimTemplate
        snapshot = BridgeSnapshot(battery: DeviceInfo.currentBattery(), transport: "none", is24Hour: DeviceInfo.is24Hour(),
                                  version: DeviceInfo.version(), pcs: [], canListen: dictation.available)
        super.init()
        dictation.emit = { [weak self] kind, text, id in self?.runScript(BridgeScripts.speech(kind: kind, text: text, id: id)) }
        observe()
        Task { await refreshComputers() }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    nonisolated static func bundledShim() -> String? {
        guard let url = Bundle.main.url(forResource: "bridge-shim", withExtension: "js") else {
            log.error("bridge-shim.js missing from the app bundle; the panel runs without window.Android")
            return nil
        }
        do { return try String(contentsOf: url, encoding: .utf8) } catch {
            log.error("bridge-shim.js unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Registers the message handler and the main-frame-only user script. Call again to refresh the script's state before a reload.
    func install(into controller: WKUserContentController) {
        if userContent == nil { controller.add(WeakScriptHandler(self), name: Self.handlerName) }
        userContent = controller
        controller.removeAllUserScripts()
        guard let template = shimTemplate, let source = BridgeScripts.shim(template: template, key: key, snapshot: snapshot) else { return }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    // MARK: messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        let result = BridgeValidator.parse(isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host,
                                           expectedKey: key, body: message.body)
        switch result {
        case .success(let command): handle(command)
        case .failure(let reason): Self.log.error("bridge message refused: \(String(describing: reason), privacy: .public)")
        }
    }

    func handle(_ command: BridgeCommand) {
        switch command {
        case .haptic: haptics.impact()
        case .buzz(let pattern): haptics.buzz(pattern)
        case .setBrightness(let value): brightness.request(value)
        case .setOrientation(let mode): orientation.set(mode)
        case .selectPc(let id): Task { await selectComputer(id) }
        case .forgetPc(let id): Task { await forgetComputer(id) }
        case .listen(let id, let lang, let offline): dictation.start(id: id, lang: lang, offline: offline)
        case .stopListening(let id): dictation.stop(id: id)
        case .cancelListening(let id): dictation.cancel(id: id)
        }
    }

    // MARK: paired computers

    private func selectComputer(_ id: String) async {
        guard let computers, await computers.computers.computers.contains(where: { $0.id == id }) else { return }
        do { try await computers.select(id) } catch {
            Self.log.error("switching computer failed: \(String(describing: error), privacy: .public)")
            return
        }
        await refreshComputers(notify: false)
        // the user script is built once per call; give the new page the new list
        if let userContent { install(into: userContent) }
        reloadPanel()
    }

    private func forgetComputer(_ id: String) async {
        guard let computers else { return }
        do { try await computers.forget(id) } catch {
            Self.log.error("forgetting computer failed: \(String(describing: error), privacy: .public)")
            return
        }
        await refreshComputers()
    }

    func refreshComputers(notify: Bool = true) async {
        guard let computers else { return }
        let list = BridgeSnapshot.computers(await computers.computers)
        snapshot.transport = await computers.route.rawValue
        guard list != snapshot.pcs else { return }
        snapshot.pcs = list
        if notify { push(BridgeUpdate(pcs: list)) }
    }

    // MARK: pushes and lifecycle

    func push(_ update: BridgeUpdate) {
        if let battery = update.battery { snapshot.battery = battery }
        if let pcs = update.pcs { snapshot.pcs = pcs }
        if let script = BridgeScripts.update(update) { runScript(script) }
    }

    private func observe() {
        let center = NotificationCenter.default
        func listen(_ name: Notification.Name, _ action: @escaping @MainActor (NativeBridge) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
            })
        }
        listen(UIDevice.batteryLevelDidChangeNotification) { $0.push(BridgeUpdate(battery: DeviceInfo.currentBattery())) }
        listen(UIDevice.batteryStateDidChangeNotification) { $0.push(BridgeUpdate(battery: DeviceInfo.currentBattery())) }
        listen(.phoneBoxComputersChanged) { bridge in Task { await bridge.refreshComputers() } }
        listen(UIApplication.willResignActiveNotification) { $0.dictation.cancel(id: 0); $0.brightness.suspend() }
        listen(UIApplication.didEnterBackgroundNotification) { $0.dictation.cancel(id: 0); $0.brightness.suspend() }
        listen(UIApplication.didBecomeActiveNotification) { bridge in
            bridge.brightness.resume()
            bridge.push(BridgeUpdate(battery: DeviceInfo.currentBattery()))
            Task { await bridge.refreshComputers() }
        }
    }
}

/// WKUserContentController keeps its handlers alive; this keeps only a weak reference to the real one.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
