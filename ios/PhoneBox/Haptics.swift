import AudioToolbox
import CoreHaptics
import os
import UIKit

@MainActor
protocol HapticsPlaying: AnyObject {
    func impact()
    func buzz(_ pattern: [Int])
}

/// Turns Android's "wait, vibrate, wait, vibrate..." millisecond list into timed pulses (seconds).
enum HapticPattern {
    struct Pulse: Equatable {
        let start: Double
        let duration: Double
    }

    static func pulses(_ pattern: [Int]) -> [Pulse] {
        var cursor = 0.0
        var result: [Pulse] = []
        for (index, ms) in pattern.enumerated() {
            let seconds = Double(ms) / 1000
            if index % 2 == 1, seconds > 0 { result.append(Pulse(start: cursor, duration: seconds)) }
            cursor += seconds
        }
        return result
    }
}

/// Tap and notification vibration. Core Haptics where the phone has a Taptic Engine, the system vibration otherwise.
@MainActor
final class Haptics: HapticsPlaying {
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "haptics")
    private var engine: CHHapticEngine?

    func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func buzz(_ pattern: [Int]) {
        let pulses = HapticPattern.pulses(pattern)
        guard !pulses.isEmpty else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { fallback(); return }
        do {
            let engine = try readyEngine()
            let events = pulses.map {
                CHHapticEvent(eventType: .hapticContinuous,
                              parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                           CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
                              relativeTime: $0.start, duration: $0.duration)
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Self.log.error("buzz failed, using system vibration: \(String(describing: error), privacy: .public)")
            fallback()
        }
    }

    private func readyEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let created = try CHHapticEngine()
        created.isAutoShutdownEnabled = true
        created.resetHandler = { [weak created] in try? created?.start() }
        try created.start()
        engine = created
        return created
    }

    private func fallback() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
