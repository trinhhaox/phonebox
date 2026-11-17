import XCTest
@testable import PhoneBox

@MainActor
private final class FakeEngine: SpeechEngine {
    var isAvailable = true
    var permission: SpeechPermission = .granted
    var deferPermission = false
    var startError: SpeechStartError?
    var started: [(lang: String, onDevice: Bool)] = []
    var stops = 0
    var cancels = 0
    var pendingAnswer: (@MainActor (SpeechPermission) -> Void)?
    var permissionRequests = 0
    var onEvent: (@MainActor (SpeechEvent) -> Void)?

    func requestPermissions(_ done: @escaping @MainActor (SpeechPermission) -> Void) {
        permissionRequests += 1
        if deferPermission { pendingAnswer = done } else { done(permission) }
    }
    func start(lang: String, onDevice: Bool, onEvent: @escaping @MainActor (SpeechEvent) -> Void) throws {
        if let startError { throw startError }
        started.append((lang, onDevice))
        self.onEvent = onEvent
        onEvent(.ready)
    }
    func stop() { stops += 1 }
    func cancel() { cancels += 1 }
}

@MainActor
final class SpeechDictationTests: XCTestCase {
    private var events: [String] = []

    private func make(_ engine: FakeEngine, limit: Duration = .seconds(60)) -> SpeechDictation {
        let dictation = SpeechDictation(engine: engine, timeLimit: limit)
        dictation.emit = { [unowned self] kind, text, id in events.append("\(kind):\(text):\(id)") }
        return dictation
    }

    func testHappyPathPartialThenFinal() {
        let engine = FakeEngine()
        let d = make(engine)
        d.start(id: 1, lang: "vi-VN", offline: false)
        XCTAssertEqual(d.state, .listening(id: 1))
        engine.onEvent?(.partial("xin"))
        engine.onEvent?(.final("xin chào"))
        XCTAssertEqual(events, ["ready::1", "partial:xin:1", "final:xin chào:1"])
        XCTAssertEqual(d.state, .idle)
        XCTAssertEqual(engine.started.first?.lang, "vi-VN")
        engine.onEvent?(.partial("late"))
        XCTAssertEqual(events.count, 3, "events after the end are ignored")
    }

    func testPermissionDeniedThenBlocked() {
        let engine = FakeEngine()
        let d = make(engine)
        engine.permission = .denied
        d.start(id: 1, lang: "", offline: false)
        engine.permission = .blocked
        d.start(id: 2, lang: "", offline: false)
        XCTAssertEqual(events, ["error:permission:1", "error:permission-blocked:2"])
        XCTAssertTrue(engine.started.isEmpty)
        XCTAssertEqual(d.state, .idle)
    }

    func testUnavailableRecognizer() {
        let engine = FakeEngine()
        engine.isAvailable = false
        let d = make(engine)
        XCTAssertFalse(d.available)
        d.start(id: 5, lang: "", offline: false)
        XCTAssertEqual(events, ["error:unavailable:5"])
        XCTAssertEqual(d.state, .idle)
    }

    func testStartFailuresMapToCodes() {
        let engine = FakeEngine()
        let d = make(engine)
        engine.startError = .offlineUnavailable
        d.start(id: 1, lang: "vi", offline: true)
        engine.startError = .failed
        d.start(id: 2, lang: "vi", offline: false)
        XCTAssertEqual(events, ["error:offline-unavailable:1", "error:unavailable:2"])
        XCTAssertEqual(d.state, .idle)
    }

    func testOfflineIsPassedToEngine() {
        let engine = FakeEngine()
        make(engine).start(id: 1, lang: "en-US", offline: true)
        XCTAssertEqual(engine.started.first?.onDevice, true)
    }

    func testRecognizerFailureEndsSession() {
        let engine = FakeEngine()
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        engine.onEvent?(.failed("7"))
        XCTAssertEqual(events.last, "error:7:1")
        XCTAssertEqual(d.state, .idle)
    }

    func testNewSessionCancelsRunningOne() {
        let engine = FakeEngine()
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        d.start(id: 2, lang: "", offline: false)
        XCTAssertEqual(events, ["ready::1", "error:cancelled:1", "ready::2"])
        XCTAssertEqual(d.state, .listening(id: 2))
    }

    func testRequestWaitingForPermissionIsReplacedWithoutSecondPrompt() {
        let engine = FakeEngine()
        engine.deferPermission = true
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        d.start(id: 2, lang: "", offline: false)
        XCTAssertEqual(engine.permissionRequests, 1)
        XCTAssertEqual(events, ["error:cancelled:1"])
        engine.pendingAnswer?(.granted)
        XCTAssertEqual(d.state, .listening(id: 2))
    }

    func testStopOnlyActsOnItsOwnSession() {
        let engine = FakeEngine()
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        d.stop(id: 9)
        XCTAssertEqual(engine.stops, 0)
        d.stop(id: 1)
        XCTAssertEqual(engine.stops, 1)
    }

    func testCancelByIdAndByBackgrounding() {
        let engine = FakeEngine()
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        d.cancel(id: 4)
        XCTAssertEqual(d.state, .listening(id: 1))
        d.cancel(id: 0)
        XCTAssertEqual(events.last, "error:cancelled:1")
        XCTAssertEqual(d.state, .idle)
    }

    func testBackgroundingKeepsRequestWaitingForPrompt() {
        let engine = FakeEngine()
        engine.deferPermission = true
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        d.cancel(id: 0)
        XCTAssertEqual(d.state, .waitingPermission(id: 1))
        d.cancel(id: 1)
        XCTAssertEqual(events, ["error:cancelled:1"])
        XCTAssertEqual(d.state, .idle)
    }

    func testTimeLimitStopsListening() async throws {
        let engine = FakeEngine()
        let d = make(engine, limit: .milliseconds(30))
        d.start(id: 1, lang: "", offline: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(engine.stops, 1)
    }

    func testLongTextIsCut() {
        let engine = FakeEngine()
        let d = make(engine)
        d.start(id: 1, lang: "", offline: false)
        engine.onEvent?(.final(String(repeating: "x", count: 5000)))
        XCTAssertEqual(events.last?.count, "final::1".count + SpeechDictation.maxChars)
    }
}
