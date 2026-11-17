import os
import WebKit

/// Lets non-view code (the event stream) talk to the panel's web view.
@MainActor
final class PanelController {
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "panel")
    weak var webView: WKWebView?

    func deliverStream(event: String, data: String) {
        webView?.evaluateJavaScript(JSQuote.streamCall(event: event, data: data)) { _, error in
            if let error { Self.log.error("onAgentStream failed: \(String(describing: error), privacy: .public)") }
        }
    }
}
