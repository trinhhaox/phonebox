import Foundation

/// What to do with a navigation requested inside one of the app's web views.
enum NavigationDecision: Equatable {
    case allow
    /// A web link to somewhere else: hand it to the default browser, never load it here.
    case openExternally
    case block
}

enum WebNavigationPolicy {
    static func decide(for url: URL?) -> NavigationDecision {
        if AgentEndpoint.isAllowed(url) || AgentEndpoint.isBlank(url) { return .allow }
        switch url?.scheme?.lowercased() {
        case "http", "https", "mailto": return .openExternally
        default: return .block
        }
    }
}
