import Foundation
import WebKit

/// Serves the panel for the `pbapp` scheme: bundled assets plus the native `/agent/*` proxy, all on one origin so the
/// panel's relative fetches work unchanged (the WebView itself never touches the network).
@MainActor
final class PanelSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "pbapp"
    static let entryURL = URL(string: "pbapp://panel/index.html")!

    private let assets: PanelAssets?
    private let proxy: any AgentProxy
    /// Tasks WebKit has not stopped yet. Calling didReceive/didFinish on a stopped task raises an exception.
    private var active = Set<ObjectIdentifier>()

    init(assets: PanelAssets? = PanelAssets(), proxy: any AgentProxy) {
        self.assets = assets
        self.proxy = proxy
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        active.insert(id)
        let request = urlSchemeTask.request
        guard let url = request.url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            finish(urlSchemeTask, id, status: 400, contentType: "text/plain", body: Data())
            return
        }
        let path = comps.path
        if PanelRequestGate.isAgentPath(path) {
            handleAgent(urlSchemeTask, id, request: request, comps: comps)
        } else if request.httpMethod?.uppercased() ?? "GET" == "GET" {
            handleAsset(urlSchemeTask, id, path: path)
        } else {
            finish(urlSchemeTask, id, status: 405, contentType: "text/plain", body: Data())
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        active.remove(ObjectIdentifier(urlSchemeTask))
    }

    private func handleAsset(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier, path: String) {
        guard let file = assets?.fileURL(forPath: path) else {
            finish(task, id, status: 404, contentType: "text/plain", body: Data())
            return
        }
        do {
            let data = try Data(contentsOf: file)
            finish(task, id, status: 200, contentType: PanelAssets.mimeType(forExtension: file.pathExtension), body: data)
        } catch {
            NSLog("PanelSchemeHandler: reading \(file.lastPathComponent) failed: \(error.localizedDescription)")
            finish(task, id, status: 500, contentType: "text/plain", body: Data())
        }
    }

    private func handleAgent(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier, request: URLRequest, comps: URLComponents) {
        let method = request.httpMethod?.uppercased() ?? "GET"
        guard PanelRequestGate.isFromPanel(method: method, path: comps.path, headers: request.allHTTPHeaderFields ?? [:]) else {
            finish(task, id, status: 403, contentType: "text/plain", body: Data())
            return
        }
        guard method == "GET" || method == "POST" else {
            finish(task, id, status: 405, contentType: "text/plain", body: Data())
            return
        }
        // keep the encoded form: the agent expects the same bytes the panel produced
        let encodedPath = String(comps.percentEncodedPath.dropFirst("/agent".count))
        let query = comps.percentEncodedQuery.map { "?\($0)" } ?? ""
        let proxy = self.proxy
        Task { [weak self] in
            let reply = await proxy.forward(method: method, pathAndQuery: encodedPath + query)
            self?.finish(task, id, status: reply.status, contentType: reply.contentType ?? "application/octet-stream", body: reply.body)
        }
    }

    /// Delivers a complete response unless WebKit already stopped the task.
    private func finish(_ task: any WKURLSchemeTask, _ id: ObjectIdentifier, status: Int, contentType: String, body: Data) {
        guard active.remove(id) != nil, let url = task.request.url else { return }
        let headers = ["Content-Type": contentType, "Content-Length": String(body.count), "Cache-Control": "no-store"]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
