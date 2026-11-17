import Foundation

enum SpeechPermission: Equatable { case granted, denied, blocked }

enum SpeechEvent: Equatable {
    case ready
    case partial(String)
    case final(String)
    /// An error code the panel's dictate widget understands (`"7"` no match, `"2"` network, ...).
    case failed(String)
}

enum SpeechStartError: Error, Equatable {
    case unavailable, offlineUnavailable, failed
}

/// The recognizer behind the state machine; the real one wraps SFSpeechRecognizer, tests use a fake.
@MainActor
protocol SpeechEngine: AnyObject {
    var isAvailable: Bool { get }
    func requestPermissions(_ done: @escaping @MainActor (SpeechPermission) -> Void)
    /// Starts listening; `onEvent` receives `ready`, partials, then exactly one `final` or `failed`.
    func start(lang: String, onDevice: Bool, onEvent: @escaping @MainActor (SpeechEvent) -> Void) throws
    /// Stops listening and lets the recognizer deliver what it heard.
    func stop()
    /// Drops the session without any further event.
    func cancel()
}

/// Dictation sessions for the panel (port of Android `Dictation`): one at a time, at most `timeLimit` long, each with an id
/// so a widget only ever hears about its own session. Results go out as `emit(kind, text, id)` with kind
/// ready | partial | final | error; for `error` the text is the code. Nothing is stored.
@MainActor
final class SpeechDictation {
    static let maxChars = 2000

    enum State: Equatable {
        case idle
        case waitingPermission(id: Int)
        case listening(id: Int)
    }

    private struct Request {
        let id: Int
        let lang: String
        let offline: Bool
    }

    private let engine: any SpeechEngine
    private let timeLimit: Duration
    private var pending: Request?
    private var timer: Task<Void, Never>?
    private(set) var state: State = .idle
    var emit: (_ kind: String, _ text: String, _ id: Int) -> Void = { _, _, _ in }

    init(engine: any SpeechEngine, timeLimit: Duration = .seconds(60)) {
        self.engine = engine
        self.timeLimit = timeLimit
    }

    var available: Bool { engine.isAvailable }

    /// Starts a session with the id the panel already holds; asks for the microphone and speech permissions first if needed.
    func start(id: Int, lang: String, offline: Bool) {
        let request = Request(id: id, lang: lang, offline: offline)
        if case .listening(let running) = state { endSession(); send("error", "cancelled", running) }
        // a newer request replaces one still waiting for the permission prompt
        let asking = pending != nil
        if let waiting = pending { send("error", "cancelled", waiting.id) }
        pending = request
        state = .waitingPermission(id: id)
        guard !asking else { return }
        engine.requestPermissions { [weak self] result in self?.permissionAnswered(result) }
    }

    /// Stops listening and delivers what was heard so far, if `id` is the session running.
    func stop(id: Int) {
        if case .listening(let running) = state, running == id { engine.stop() }
    }

    /// Drops the session without a result when `id` is the one running or waiting. 0 = whatever runs (the app left the
    /// screen); a request waiting for the permission prompt stays then, because that prompt itself leaves the screen.
    func cancel(id: Int) {
        if let waiting = pending, id != 0, waiting.id == id {
            pending = nil
            state = .idle
            send("error", "cancelled", id)
        }
        if case .listening(let running) = state, id == 0 || id == running {
            endSession()
            send("error", "cancelled", running)
        }
    }

    private func permissionAnswered(_ result: SpeechPermission) {
        guard let request = pending else { return }
        pending = nil
        state = .idle
        switch result {
        case .granted: begin(request)
        case .denied: send("error", "permission", request.id)
        case .blocked: send("error", "permission-blocked", request.id)
        }
    }

    private func begin(_ request: Request) {
        guard engine.isAvailable else { send("error", "unavailable", request.id); return }
        state = .listening(id: request.id)
        do {
            try engine.start(lang: request.lang, onDevice: request.offline) { [weak self] event in
                self?.received(event, id: request.id)
            }
        } catch {
            state = .idle
            engine.cancel()
            send("error", error as? SpeechStartError == .offlineUnavailable ? "offline-unavailable" : "unavailable", request.id)
            return
        }
        timer = Task { [weak self, timeLimit] in
            try? await Task.sleep(for: timeLimit)
            guard !Task.isCancelled else { return }
            self?.limitReached(id: request.id)
        }
    }

    private func limitReached(id: Int) {
        if case .listening(let running) = state, running == id { engine.stop() }
    }

    private func received(_ event: SpeechEvent, id: Int) {
        guard case .listening(let running) = state, running == id else { return }
        switch event {
        case .ready: send("ready", "", id)
        case .partial(let text): send("partial", text, id)
        case .final(let text): endSession(); send("final", text, id)
        case .failed(let code): endSession(); send("error", code, id)
        }
    }

    private func endSession() {
        timer?.cancel()
        timer = nil
        engine.cancel()
        state = .idle
    }

    private func send(_ kind: String, _ text: String, _ id: Int) {
        emit(kind, String(text.prefix(Self.maxChars)), id)
    }
}
