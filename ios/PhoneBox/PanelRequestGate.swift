import Foundation

/// Decides which panel requests may reach the agent. Mirrors Android `MainActivity.fromPanel`: only requests that carry
/// the panel header (a sandboxed custom-HTML iframe cannot add it without a CORS preflight, which is never answered)
/// or plain GETs for the read-only image endpoints (`<img>` tags cannot set headers).
enum PanelRequestGate {
    static let panelHeader = "X-PhoneBox-Panel"
    static let agentPrefix = "/agent/"
    static let readOnlyImages: Set<String> = [
        "/agent/api/art", "/agent/api/procs/icon", "/agent/api/controls/radio-logo",
        "/agent/api/apps/icon", "/agent/api/discord/img",
    ]

    static func isAgentPath(_ path: String) -> Bool { path.hasPrefix(agentPrefix) }

    static func isFromPanel(method: String, path: String, headers: [String: String]) -> Bool {
        if headers.keys.contains(where: { $0.caseInsensitiveCompare(panelHeader) == .orderedSame }) { return true }
        return method.uppercased() == "GET" && readOnlyImages.contains(path)
    }
}
