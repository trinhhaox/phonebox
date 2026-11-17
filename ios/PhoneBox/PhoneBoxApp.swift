import SwiftUI

@main
struct PhoneBoxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            PanelRootView(model: model, pairing: model.pairing)
        }
        .onChange(of: scenePhase) { phase in
            // the panel is a wall display: never dim while it is on screen
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
            if phase == .active { model.stream.start() } else if phase == .background { model.stream.stop() }
        }
    }
}

/// The panel plus everything pairing puts on top of it: native menu, confirmation, result notices, deep links.
struct PanelRootView: View {
    let model: AppModel
    @ObservedObject var pairing: PairingModel

    var body: some View {
        PanelView(proxy: model.link, controller: model.controller, onMenuRequest: { pairing.showMenu = true })
            .background(Color.black)
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .overlay { if pairing.isClaiming { ProgressView("Đang ghép nối...").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .sheet(isPresented: $pairing.showMenu) { NativeMenuView(model: pairing, panelVersion: model.identity.appVersion) }
            .alert("Ghép nối máy tính?", isPresented: Binding(get: { pairing.pending != nil }, set: { if !$0 { pairing.cancelPending() } }),
                   presenting: pairing.pending) { _ in
                Button("Ghép nối") { pairing.confirmPending() }
                Button("Huỷ", role: .cancel) {}
            } message: { link in
                Text("Ghép nối với \"\(link.pc)\" tại \(link.hosts.joined(separator: ", ")) (cổng \(link.port))? Kiểm tra máy tính đang hiện mã \(link.check).")
            }
            .alert("PhoneBox", isPresented: Binding(get: { pairing.notice != nil }, set: { if !$0 { pairing.dismissNotice() } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(pairing.notice ?? "") }
            .onOpenURL { pairing.offer(url: $0) }
            .task { await pairing.start() }
    }
}

/// Long-lived objects shared by the panel, the stream and pairing.
@MainActor
final class AppModel {
    let controller = PanelController()
    let identity = DeviceIdentity.current()
    let link: AgentLink
    let stream: AgentStream
    let pairing: PairingModel

    init() {
        let controller = self.controller
        let link = AgentLink(identity: identity)
        let stream = AgentStream(source: link) { event, data in controller.deliverStream(event: event, data: data) }
        self.link = link
        self.stream = stream
        pairing = PairingModel(link: link, claimer: PairingClaim(model: identity.model)) { [weak controller] in
            // the active computer or its addresses changed: reconnect the stream and show the new computer's panel
            stream.stop()
            stream.start()
            controller?.webView?.reload()
        }
    }
}
