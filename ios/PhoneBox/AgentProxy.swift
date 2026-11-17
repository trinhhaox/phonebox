import Foundation

/// Buffered answer from the agent (or a synthetic one when it is unreachable).
struct AgentReply {
    let status: Int
    let contentType: String?
    let body: Data

    static func json(_ status: Int, _ text: String) -> AgentReply {
        AgentReply(status: status, contentType: "application/json", body: Data(text.utf8))
    }
}

/// Where `/agent/*` requests from the panel end up. `pathAndQuery` is already stripped of `/agent`
/// and keeps the query percent-encoded, e.g. `/api/state?x=1`.
protocol AgentProxy: Sendable {
    func forward(method: String, pathAndQuery: String) async -> AgentReply
}

/// Used until a computer is paired: every request is answered like the Android app does when offline.
struct OfflineAgentProxy: AgentProxy {
    func forward(method: String, pathAndQuery: String) async -> AgentReply {
        .json(503, #"{"error":"offline"}"#)
    }
}
