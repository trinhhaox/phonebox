import Foundation

enum AgentInstallerError: LocalizedError {
    case scriptMissing
    var errorDescription: String? { "Không tìm thấy setup.sh trong ứng dụng" }
}

/// Runs the bundled setup.sh as the current user (never sudo). setup.sh downloads the release from GitHub
/// and verifies its SHA-256 itself.
enum AgentInstaller {
    static let scriptName = "setup"
    static let scriptExtension = "sh"

    struct Command: Equatable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
    }

    static func bundledScript(in bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(forResource: scriptName, withExtension: scriptExtension) else {
            throw AgentInstallerError.scriptMissing
        }
        return url
    }

    /// `/bin/bash <setup.sh> --yes --no-phone`: unattended, and without the USB phone-app step (that needs a phone and adb).
    static func command(script: URL, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> Command {
        var env = baseEnvironment
        // Apps started from Finder get a minimal PATH; setup.sh needs curl/brew/etc. from the usual places.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["NO_COLOR"] = "1"
        return Command(executable: URL(fileURLWithPath: "/bin/bash"),
                       arguments: [script.path, "--yes", "--no-phone"], environment: env)
    }

    /// Removes terminal colour escape sequences so the log window shows plain text.
    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    /// Streams the combined output line by line; the stream finishes with the exit status or throws if it cannot start.
    static func run(_ command: Command) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = command.executable
            process.arguments = command.arguments
            process.environment = command.environment
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let buffer = LineBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in buffer.append(data) { continuation.yield(.line(stripANSI(line))) }
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                for line in buffer.append(rest) + buffer.flush() { continuation.yield(.line(stripANSI(line))) }
                continuation.yield(.finished(status: finished.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { _ in if process.isRunning { process.terminate() } }
            do { try process.run() } catch { continuation.finish(throwing: error) }
        }
    }

    enum Event: Equatable {
        case line(String)
        case finished(status: Int32)
    }
}

/// Splits arbitrary data chunks into lines (setup.sh prints progress with \r and \n).
final class LineBuffer: @unchecked Sendable {
    private var pending = ""
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending += String(decoding: data, as: UTF8.self)
        var lines = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        pending = lines.removeLast()
        return lines.filter { !$0.isEmpty }
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        defer { pending = "" }
        return pending.isEmpty ? [] : [pending]
    }
}
