import WebKit
import XCTest
@testable import PhoneBox

private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: HTTPURLResponse?
    var received = Data()
    var finished = false
    var onFinish: (() -> Void)?
    var status: Int? { response?.statusCode }
    var mime: String? { response?.value(forHTTPHeaderField: "Content-Type") }

    init(_ url: String, method: String = "GET", headers: [String: String] = [:]) {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = method
        r.allHTTPHeaderFields = headers
        request = r
    }

    func didReceive(_ response: URLResponse) { self.response = response as? HTTPURLResponse }
    func didReceive(_ data: Data) { received.append(data) }
    func didFinish() { finished = true; onFinish?() }
    func didFailWithError(_ error: any Error) { XCTFail("task failed: \(error)") }
}

private struct RecordingProxy: AgentProxy {
    let log = Box()
    final class Box: @unchecked Sendable { var calls: [String] = [] }
    func forward(method: String, pathAndQuery: String) async -> AgentReply {
        log.calls.append("\(method) \(pathAndQuery)")
        return .json(200, #"{"ok":true}"#)
    }
}

@MainActor
final class PanelSchemeHandlerTests: XCTestCase {
    private func run(_ task: FakeSchemeTask, proxy: RecordingProxy = RecordingProxy()) async {
        let handler = PanelSchemeHandler(proxy: proxy)
        let done = expectation(description: "finished")
        task.onFinish = { done.fulfill() }
        handler.webView(WKWebView(), start: task)
        await fulfillment(of: [done], timeout: 5)
    }

    func testGateRequiresPanelHeader() {
        XCTAssertTrue(PanelRequestGate.isFromPanel(method: "GET", path: "/agent/api/state", headers: ["x-phonebox-panel": "1"]))
        XCTAssertFalse(PanelRequestGate.isFromPanel(method: "GET", path: "/agent/api/state", headers: [:]))
        XCTAssertFalse(PanelRequestGate.isFromPanel(method: "POST", path: "/agent/api/macro", headers: ["Other": "1"]))
    }

    func testGateAllowsReadOnlyImageGetsOnly() {
        XCTAssertTrue(PanelRequestGate.isFromPanel(method: "GET", path: "/agent/api/art", headers: [:]))
        XCTAssertFalse(PanelRequestGate.isFromPanel(method: "POST", path: "/agent/api/art", headers: [:]))
        XCTAssertFalse(PanelRequestGate.isFromPanel(method: "GET", path: "/agent/api/art/../state", headers: [:]))
    }

    func testPathTraversalIsRejected() throws {
        let assets = try XCTUnwrap(PanelAssets())
        XCTAssertNotNil(assets.fileURL(forPath: "/index.html"))
        XCTAssertNotNil(assets.fileURL(forPath: "/"))
        XCTAssertNil(assets.fileURL(forPath: "/../Info.plist"))
        XCTAssertNil(assets.fileURL(forPath: "/widgets/../../Info.plist"))
        XCTAssertNil(assets.fileURL(forPath: "/nope.js"))
        XCTAssertNil(assets.fileURL(forPath: "/widgets"))
    }

    func testMimeTypes() {
        XCTAssertEqual(PanelAssets.mimeType(forExtension: "js"), "text/javascript; charset=utf-8")
        XCTAssertEqual(PanelAssets.mimeType(forExtension: "CSS"), "text/css; charset=utf-8")
        XCTAssertEqual(PanelAssets.mimeType(forExtension: "xyz"), "application/octet-stream")
    }

    func testAgentWithoutHeaderGets403AndProxyIsNotCalled() async {
        let proxy = RecordingProxy()
        let task = FakeSchemeTask("pbapp://panel/agent/api/state")
        await run(task, proxy: proxy)
        XCTAssertEqual(task.status, 403)
        XCTAssertTrue(proxy.log.calls.isEmpty)
    }

    func testAgentWithHeaderIsProxiedWithEncodedQuery() async {
        let proxy = RecordingProxy()
        let task = FakeSchemeTask("pbapp://panel/agent/api/x%20y?a=1&b=%2F", headers: ["X-PhoneBox-Panel": "1"])
        await run(task, proxy: proxy)
        XCTAssertEqual(task.status, 200)
        XCTAssertEqual(proxy.log.calls, ["GET /api/x%20y?a=1&b=%2F"])
    }

    func testOfflineProxyAnswers503() async {
        let task = FakeSchemeTask("pbapp://panel/agent/api/state", headers: ["X-PhoneBox-Panel": "1"])
        let handler = PanelSchemeHandler(proxy: OfflineAgentProxy())
        let done = expectation(description: "finished")
        task.onFinish = { done.fulfill() }
        handler.webView(WKWebView(), start: task)
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(task.status, 503)
        XCTAssertEqual(String(data: task.received, encoding: .utf8), #"{"error":"offline"}"#)
    }

    func testServesIndexWithHtmlMime() async {
        let task = FakeSchemeTask("pbapp://panel/index.html")
        await run(task)
        XCTAssertEqual(task.status, 200)
        XCTAssertEqual(task.mime, "text/html; charset=utf-8")
    }

    func testServesModuleScriptAsJavaScript() async {
        let task = FakeSchemeTask("pbapp://panel/main.js")
        await run(task)
        XCTAssertEqual(task.mime, "text/javascript; charset=utf-8")
    }

    func testStoppedTaskIsNotAnswered() async {
        let handler = PanelSchemeHandler(proxy: RecordingProxy())
        let task = FakeSchemeTask("pbapp://panel/agent/api/state", headers: ["X-PhoneBox-Panel": "1"])
        handler.webView(WKWebView(), start: task)
        handler.webView(WKWebView(), stop: task)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(task.finished)
    }
}
