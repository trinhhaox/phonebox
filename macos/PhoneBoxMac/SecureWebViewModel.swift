import AppKit
import OSLog
import WebKit

/// Owns one WKWebView that may only ever show the local agent (http://127.0.0.1:8765).
/// Other web links open in the default browser; every other scheme is blocked.
@MainActor
final class SecureWebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let url: URL
    private let logger = Logger(subsystem: "vn.xox.phonebox.mac", category: "web")
    private var pendingPairing = false

    init(url: URL) {
        precondition(AgentEndpoint.isAllowed(url), "SecureWebViewModel only loads the local agent")
        self.url = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        load()
    }

    func load() { webView.load(URLRequest(url: url)) }

    func reload() {
        if webView.url == nil || AgentEndpoint.isBlank(webView.url) { load() } else { webView.reload() }
    }

    /// Opens the "Pair a phone over Wi-Fi" dialog of the settings page (the page has no deep link for it).
    func openPairingDialog() {
        if webView.isLoading || webView.url == nil {
            pendingPairing = true
        } else {
            runPairingScript()
        }
    }

    private func runPairingScript() {
        let js = """
        (() => { const b = document.getElementById('lanPair'); if (!b) return false;
          if (location.hash !== '#general') location.hash = '#general';
          b.scrollIntoView({ block: 'center' }); b.click(); return true; })()
        """
        webView.evaluateJavaScript(js) { [logger] result, error in
            if let error { logger.error("pairing script failed: \(error.localizedDescription, privacy: .public)") }
            else if (result as? Bool) != true { logger.notice("pairing button not found on the settings page") }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(route(navigationAction.request.url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard pendingPairing, AgentEndpoint.isAllowed(webView.url) else { return }
        pendingPairing = false
        runPairingScript()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showOffline(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showOffline(error)
    }

    // MARK: WKUIDelegate

    /// window.open / target=_blank: never create a second web view, just route the URL.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let decision = route(navigationAction.request.url)
        if decision == .allow, let target = navigationAction.request.url { webView.load(URLRequest(url: target)) }
        return nil
    }

    // MARK: Helpers

    private func route(_ target: URL?) -> WKNavigationActionPolicy {
        switch WebNavigationPolicy.decide(for: target) {
        case .allow:
            return .allow
        case .openExternally:
            if let target { NSWorkspace.shared.open(target) }
            return .cancel
        case .block:
            logger.notice("blocked navigation to \(target?.scheme ?? "?", privacy: .public) URL")
            return .cancel
        }
    }

    /// Agent down or restarting: show a message and retry on its own. A load interrupted by our own cancel (-999) is ignored.
    private func showOffline(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        logger.notice("agent page unavailable: \(nsError.localizedDescription, privacy: .public)")
        let html = """
        <html><body style="font:15px -apple-system;background:#1c1c1e;color:#ddd;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center">
        <div><div style="font-size:34px">&#9888;&#65039;</div><p>Chưa kết nối được PhoneBox agent.<br>Đang thử lại…</p></div>
        <script>setTimeout(() => { location.href = '\(url.absoluteString)'; }, 3000);</script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
