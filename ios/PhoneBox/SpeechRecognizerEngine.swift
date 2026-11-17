import AVFoundation
import os
import Speech

/// SFSpeechRecognizer + AVAudioEngine behind `SpeechEngine`. On-device recognition is used only when asked for and
/// supported; it never silently falls back to Apple's servers.
@MainActor
final class SpeechRecognizerEngine: SpeechEngine {
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "dictation")
    private var audio: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onEvent: (@MainActor (SpeechEvent) -> Void)?
    private var previousAudio: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    var isAvailable: Bool { SFSpeechRecognizer(locale: .current)?.isAvailable ?? false }

    func requestPermissions(_ done: @escaping @MainActor (SpeechPermission) -> Void) {
        let session = AVAudioSession.sharedInstance()
        let speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .denied || speech == .restricted || session.recordPermission == .denied { done(.blocked); return }
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { Task { @MainActor in done(.denied) }; return }
            session.requestRecordPermission { granted in
                Task { @MainActor in done(granted ? .granted : .denied) }
            }
        }
    }

    func start(lang: String, onDevice: Bool, onEvent: @escaping @MainActor (SpeechEvent) -> Void) throws {
        cancel()
        let locale = lang.isEmpty ? Locale.current : Locale(identifier: lang)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw SpeechStartError.unavailable }
        if onDevice && !recognizer.supportsOnDeviceRecognition { throw SpeechStartError.offlineUnavailable }
        self.onEvent = onEvent
        do {
            try startCapture(recognizer: recognizer, onDevice: onDevice)
        } catch {
            Self.log.error("dictation start failed: \(String(describing: error), privacy: .public)")
            cancel()
            throw SpeechStartError.failed
        }
        onEvent(.ready)
    }

    func stop() {
        stopAudio()
        request?.endAudio()
    }

    func cancel() {
        onEvent = nil
        task?.cancel()
        task = nil
        stopAudio()
        request = nil
        restoreAudioSession()
    }

    private func startCapture(recognizer: SFSpeechRecognizer, onDevice: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        previousAudio = (session.category, session.mode, session.categoryOptions)
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        self.request = request
        let engine = AVAudioEngine()
        audio = engine
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechStartError.unavailable }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let code = error.map(Self.errorCode)
            Task { @MainActor in self?.deliver(text: text, isFinal: isFinal, errorCode: code) }
        }
    }

    private func deliver(text: String?, isFinal: Bool, errorCode: String?) {
        guard let onEvent else { return }
        if isFinal { onEvent(.final(text ?? "")) }
        else if let errorCode { onEvent(.failed(errorCode)) }
        else if let text { onEvent(.partial(text)) }
    }

    private func stopAudio() {
        guard let engine = audio else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        audio = nil
    }

    private func restoreAudioSession() {
        guard let previous = previousAudio else { return }
        previousAudio = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(previous.category, mode: previous.mode, options: previous.options)
        } catch {
            Self.log.error("audio session restore failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Codes borrowed from Android's SpeechRecognizer so the panel's messages fit: 2 = network, 7 = nothing recognised.
    nonisolated static func errorCode(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "2" }
        if ns.domain == "kAFAssistantErrorDomain", [1100, 1101, 1107].contains(ns.code) { return "2" }
        return "7"
    }
}
