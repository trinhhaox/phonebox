import SwiftUI
import WebKit

struct SecureWebView: NSViewRepresentable {
    let model: SecureWebViewModel

    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
