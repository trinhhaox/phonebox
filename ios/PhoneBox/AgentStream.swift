import Foundation
import os

/// Opens the agent's event stream; implemented by [AgentLink], faked in tests.
protocol StreamSource: Sendable {
    func openStream() async throws -> AsyncThrowingStream<String, Error>
}

extension AgentLink: StreamSource {}

/// Keeps one live connection to /api/stream and hands every event to `deliver` (on the main actor). "open" / "close"
/// pseudo-events tell the panel when to stop or resume its polling fallback. Reconnects after errors and once a minute.
@MainActor
final class AgentStream {
    static let maxLifetime: TimeInterval = 60
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "stream")

    private let source: any StreamSource
    private let deliver: @MainActor (_ event: String, _ data: String) -> Void
    private let reconnectDelay: (_ wasOpen: Bool) -> Duration
    // each start() bumps the generation, so a loop that is still connecting after a quick stop/start ends by itself
    private var generation = 0
    private var task: Task<Void, Never>?

    init(source: any StreamSource,
         reconnectDelay: @escaping (Bool) -> Duration = { $0 ? .milliseconds(300) : .seconds(2) },
         deliver: @escaping @MainActor (String, String) -> Void) {
        self.source = source
        self.reconnectDelay = reconnectDelay
        self.deliver = deliver
    }

    func start() {
        guard task == nil else { return }
        generation += 1
        let gen = generation
        task = Task { [weak self] in await self?.loop(gen) }
    }

    func stop() {
        task?.cancel()
        task = nil
        generation += 1
    }

    private func alive(_ gen: Int) -> Bool { gen == generation && !Task.isCancelled }

    private func loop(_ gen: Int) async {
        while alive(gen) {
            var opened = false
            do {
                let lines = try await source.openStream()
                guard alive(gen) else { return }
                opened = true
                deliver("open", #"{"route":"wifi"}"#)
                let since = ContinuousClock.now
                var parser = SSEParser()
                for try await line in lines {
                    guard alive(gen) else { break }
                    if let event = parser.feed(line: line) {
                        deliver(event.event, event.data)
                        // reconnect between events so the choice of route is re-evaluated
                        if ContinuousClock.now - since > .seconds(Self.maxLifetime) { break }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                Self.log.info("stream ended: \(String(describing: error), privacy: .public)")
            }
            if opened && gen == generation { deliver("close", "{}") }
            guard alive(gen) else { return }
            try? await Task.sleep(for: reconnectDelay(opened)) // throws only when cancelled; alive() checks that next loop
        }
    }
}

enum JSQuote {
    /// A JSON string literal, safe to splice into a script (agent-controlled text must never be interpolated raw).
    static func string(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    static func streamCall(event: String, data: String) -> String {
        "window.onAgentStream && window.onAgentStream(\(string(event)), \(string(data)))"
    }
}
