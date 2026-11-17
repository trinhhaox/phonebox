import Foundation

enum OrientationMode: String, Equatable {
    case landscape, portrait, auto
}

/// A request from the panel after validation; nothing else can reach the native handlers.
enum BridgeCommand: Equatable {
    case haptic
    case buzz([Int])
    case setBrightness(Double)
    case setOrientation(OrientationMode)
    case selectPc(String)
    case forgetPc(String)
    case listen(id: Int, lang: String, offline: Bool)
    case stopListening(Int)
    case cancelListening(Int)
}

enum BridgeRejection: Error, Equatable {
    case notMainFrame, wrongOrigin, badKey, malformed, unknownMethod
}

/// Pure checks behind `NativeBridge`: who is calling (main frame of the panel origin, per-launch key) and what they ask
/// for (allow-listed method, typed arguments). Fails closed.
enum BridgeValidator {
    static let originScheme = "pbapp"
    static let originHost = "panel"
    static let maxPatternLength = 32
    static let maxPulseMs = 5000
    static let maxLangLength = 20

    static func parse(isMainFrame: Bool, scheme: String, host: String, expectedKey: String, body: Any) -> Result<BridgeCommand, BridgeRejection> {
        guard isMainFrame else { return .failure(.notMainFrame) }
        guard scheme == originScheme, host == originHost else { return .failure(.wrongOrigin) }
        guard let dict = body as? [String: Any], let key = dict["k"] as? String, let method = dict["m"] as? String else {
            return .failure(.malformed)
        }
        guard !expectedKey.isEmpty, key == expectedKey else { return .failure(.badKey) }
        let args = dict["a"] as? [Any] ?? []
        return command(method: method, args: args)
    }

    private static func command(method: String, args: [Any]) -> Result<BridgeCommand, BridgeRejection> {
        func fail() -> Result<BridgeCommand, BridgeRejection> { .failure(.malformed) }
        switch method {
        case "haptic":
            return .success(.haptic)
        case "buzz":
            guard let text = args.first as? String, let pattern = pattern(text) else { return fail() }
            return .success(.buzz(pattern))
        case "setBrightness":
            guard let v = args.first.flatMap(number) else { return fail() }
            return .success(.setBrightness(v < 0 ? -1 : min(v, 1)))
        case "setOrientation":
            guard let raw = args.first as? String, let mode = OrientationMode(rawValue: raw) else { return fail() }
            return .success(.setOrientation(mode))
        case "selectPc", "forgetPc":
            guard let id = args.first as? String, isComputerId(id) else { return fail() }
            return .success(method == "selectPc" ? .selectPc(id) : .forgetPc(id))
        case "listen":
            guard args.count == 3, let id = args.first.flatMap(sessionId), let lang = args[1] as? String, let offline = flag(args[2]) else { return fail() }
            return .success(.listen(id: id, lang: sanitizeLanguage(lang), offline: offline))
        case "stopListening", "cancelListening":
            guard let id = args.first.flatMap(sessionId) else { return fail() }
            return .success(method == "stopListening" ? .stopListening(id) : .cancelListening(id))
        default:
            return .failure(.unknownMethod)
        }
    }

    /// "wait,vibrate,wait,..." in milliseconds. Non-numbers are dropped like Android does; too many or too long pulses are refused.
    static func pattern(_ text: String) -> [Int]? {
        let values = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !values.isEmpty, values.count <= maxPatternLength, values.allSatisfy({ (0...maxPulseMs).contains($0) }) else { return nil }
        return values
    }

    static func sanitizeLanguage(_ lang: String) -> String {
        String(lang.prefix(maxLangLength).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    }

    /// A computer id is the lowercase hex SHA-256 of its certificate.
    static func isComputerId(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    private static func number(_ value: Any) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    private static func flag(_ value: Any) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    private static func sessionId(_ value: Any) -> Int? {
        guard let d = number(value), d >= 1, d <= Double(Int32.max), d.rounded() == d else { return nil }
        return Int(d)
    }
}
