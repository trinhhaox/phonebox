import UIKit
import WebKit
import XCTest
@testable import PhoneBox

/// Loads the real bundled panel with the real shim and checks what the panel's own JavaScript sees.
/// Synchronous on purpose: an async test method crashes XCTest's error observation on this toolchain.
@MainActor
final class PanelBridgeIntegrationTests: XCTestCase, WKNavigationDelegate {
    private var loaded: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.fulfill() }

    private func eval(_ webView: WKWebView, _ script: String) -> String? {
        var result: String?
        let done = expectation(description: script)
        webView.evaluateJavaScript(script) { value, _ in result = value as? String; done.fulfill() }
        wait(for: [done], timeout: 10)
        return result
    }

    func testPanelSeesSupportedBridgeMethodsOnly() throws {
        let bridge = NativeBridge(computers: nil, haptics: Haptics(), brightness: BrightnessController(),
                                  orientation: OrientationController(), dictation: SpeechDictation(engine: SpeechRecognizerEngine()))
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PanelSchemeHandler(proxy: OfflineAgentProxy()), forURLScheme: PanelSchemeHandler.scheme)
        bridge.install(into: config.userContentController)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 844, height: 390), configuration: config)
        webView.navigationDelegate = self
        bridge.runScript = { [weak webView] in webView?.evaluateJavaScript($0, completionHandler: nil) }
        loaded = expectation(description: "panel loaded")
        webView.load(URLRequest(url: PanelSchemeHandler.entryURL))
        wait(for: [loaded!], timeout: 30)

        let list = try XCTUnwrap(eval(webView, "JSON.stringify(Object.keys(window.Android).sort())"))
        for present in ["battery", "buzz", "haptic", "listen", "pcs", "setBrightness", "setOrientation", "transport"] {
            XCTAssertTrue(list.contains("\"\(present)\""), "\(present) missing in \(list)")
        }
        for absent in ["setVolumeKeys", "setPinned", "setHomeScreen"] { XCTAssertFalse(list.contains(absent)) }
        let battery = try XCTUnwrap(eval(webView, "window.Android.battery()"))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(battery.utf8)))
        XCTAssertEqual(eval(webView, "typeof window.__phoneboxKey"), "string")

        let pause = expectation(description: "panel renders")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { pause.fulfill() }
        wait(for: [pause], timeout: 10)
        if let dir = ProcessInfo.processInfo.environment["PB_SNAPSHOT_DIR"] {
            let snap = expectation(description: "snapshot")
            webView.takeSnapshot(with: nil) { image, _ in
                try? image?.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("panel-snapshot.png"))
                snap.fulfill()
            }
            wait(for: [snap], timeout: 10)
        }
    }
}
