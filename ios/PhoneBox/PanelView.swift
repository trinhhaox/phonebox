import os
import SwiftUI
import WebKit

/// Full-screen WKWebView showing the bundled panel through `PanelSchemeHandler`.
struct PanelView: UIViewRepresentable {
    let proxy: any AgentProxy
    let controller: PanelController
    /// Called after a two-finger long press (phase 04 opens the native menu from it).
    var onMenuRequest: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        let bridge = NativeBridge(computers: proxy as? any PairedComputerSource, haptics: Haptics(), brightness: BrightnessController(),
                                  orientation: OrientationController(), dictation: SpeechDictation(engine: SpeechRecognizerEngine()))
        return Coordinator(bridge: bridge, onMenuRequest: onMenuRequest)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(PanelSchemeHandler(proxy: proxy), forURLScheme: PanelSchemeHandler.scheme)
        context.coordinator.bridge.install(into: config.userContentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        press.numberOfTouchesRequired = 2
        press.minimumPressDuration = 1.2
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        webView.addGestureRecognizer(press)

        controller.webView = webView
        let bridge = context.coordinator.bridge
        bridge.runScript = { [weak webView] script in
            webView?.evaluateJavaScript(script) { _, error in
                if let error { Logger(subsystem: "vn.xox.phonebox", category: "bridge").error("script failed: \(String(describing: error), privacy: .public)") }
            }
        }
        bridge.reloadPanel = { [weak webView] in webView?.reload() }
        webView.load(URLRequest(url: PanelSchemeHandler.entryURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMenuRequest = onMenuRequest
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let bridge: NativeBridge
        var onMenuRequest: () -> Void
        init(bridge: NativeBridge, onMenuRequest: @escaping () -> Void) {
            self.bridge = bridge
            self.onMenuRequest = onMenuRequest
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { onMenuRequest() }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
