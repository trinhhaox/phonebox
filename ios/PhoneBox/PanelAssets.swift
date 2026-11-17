import Foundation

/// Maps `pbapp://panel/<path>` onto the bundled `www` folder (a folder reference to the Android panel assets).
struct PanelAssets {
    let root: URL

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "www", withExtension: nil) else { return nil }
        root = url.standardizedFileURL
    }

    init(root: URL) { self.root = root.standardizedFileURL }

    /// The file for a decoded URL path, or nil when it escapes the folder or does not exist.
    func fileURL(forPath path: String) -> URL? {
        let relative = path == "/" || path.isEmpty ? "index.html" : String(path.drop(while: { $0 == "/" }))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }), !relative.contains("\0") else { return nil }
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return url
    }

    /// ES modules are refused by WebKit unless they are served as JavaScript.
    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
