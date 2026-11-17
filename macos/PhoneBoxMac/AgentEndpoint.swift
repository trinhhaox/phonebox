import Foundation

/// Where the desktop agent listens and which URLs the app is allowed to show.
enum AgentEndpoint {
    static let host = "127.0.0.1"
    static let port = 8765
    static let base = URL(string: "http://127.0.0.1:8765")!
    static let panelURL = URL(string: "http://127.0.0.1:8765/panel/")!
    static let settingsURL = URL(string: "http://127.0.0.1:8765/")!
    /// The settings section that holds the "Pair a phone over Wi-Fi" button.
    static let pairingURL = URL(string: "http://127.0.0.1:8765/#general")!
    static let infoURL = URL(string: "http://127.0.0.1:8765/api/info")!
    static let phonesURL = URL(string: "http://127.0.0.1:8765/api/phones")!

    /// Same-origin check: exactly http://127.0.0.1:8765 (the agent itself rejects any other Host/Origin).
    static func isAllowed(_ url: URL?) -> Bool {
        guard let url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return comps.scheme == "http" && comps.host == host && comps.port == port
            && comps.user == nil && comps.password == nil
    }

    /// about:blank is what WebKit uses for the initial load; it carries no content.
    static func isBlank(_ url: URL?) -> Bool { url?.absoluteString == "about:blank" }
}
