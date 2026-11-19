import Foundation

enum AgentControlError: LocalizedError {
    case launchctlFailed(status: Int32, output: String)
    case cannotRun(String)

    var errorDescription: String? {
        switch self {
        case let .launchctlFailed(status, output):
            return "launchctl lỗi (\(status)): \(output.isEmpty ? "không có chi tiết" : output)"
        case let .cannotRun(reason):
            return "Không chạy được launchctl: \(reason)"
        }
    }
}

enum AgentControl {
    struct ProcessResult: Equatable {
        let status: Int32
        let output: String
    }

    static func domainTarget(uid: uid_t = getuid()) -> String {
        "gui/\(uid)"
    }

    static func serviceTarget(uid: uid_t = getuid(), label: String = AgentInstallation.launchdLabel) -> String {
        "\(domainTarget(uid: uid))/\(label)"
    }

    /// `launchctl kickstart [-k] gui/<uid>/<label>`: starts or restarts the agent job. Arguments are an array, never a shell string.
    static func kickstartArguments(
        uid: uid_t = getuid(),
        label: String = AgentInstallation.launchdLabel,
        killRunning: Bool = true
    ) -> [String] {
        let target = serviceTarget(uid: uid, label: label)
        return killRunning ? ["kickstart", "-k", target] : ["kickstart", target]
    }

    static func bootoutArguments(uid: uid_t = getuid(), label: String = AgentInstallation.launchdLabel) -> [String] {
        ["bootout", serviceTarget(uid: uid, label: label)]
    }

    static func bootstrapArguments(uid: uid_t = getuid(), plistPath: String) -> [String] {
        ["bootstrap", domainTarget(uid: uid), plistPath]
    }

    static func printArguments(uid: uid_t = getuid(), label: String = AgentInstallation.launchdLabel) -> [String] {
        ["print", serviceTarget(uid: uid, label: label)]
    }

    /// `bootout` exits with 3 (ESRCH) and `kickstart`/`print` exit with 113 when the service is not loaded in `gui/<uid>`.
    static func isNotLoadedStatus(_ status: Int32) -> Bool {
        status == 3 || status == 113
    }

    static func isServiceLoaded(uid: uid_t = getuid(), label: String = AgentInstallation.launchdLabel) async -> Bool {
        guard let result = try? await runLaunchctl(printArguments(uid: uid, label: label)) else { return false }
        return result.status == 0
    }

    static func startAgent(plist: URL = AgentInstallation.standard().launchAgentPlist) async throws {
        try await kickstartOrBootstrap(killRunning: false, plist: plist)
    }

    static func restartAgent(plist: URL = AgentInstallation.standard().launchAgentPlist) async throws {
        try await kickstartOrBootstrap(killRunning: true, plist: plist)
    }

    static func stopAgent() async throws {
        let result = try await runLaunchctl(bootoutArguments())
        if result.status != 0 && !isNotLoadedStatus(result.status) {
            throw AgentControlError.launchctlFailed(status: result.status, output: result.output)
        }
        if isNotLoadedStatus(result.status) {
            _ = try? await runExecutable("/usr/bin/pkill", arguments: ["-x", "PhoneBoxAgent"])
        }
        for _ in 0..<20 {
            guard let check = try? await runExecutable("/usr/bin/pgrep", arguments: ["-x", "PhoneBoxAgent"]) else { break }
            if check.status != 0 { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private static func kickstartOrBootstrap(killRunning: Bool, plist: URL) async throws {
        let result = try await runLaunchctl(kickstartArguments(killRunning: killRunning))
        if result.status == 0 { return }
        if isNotLoadedStatus(result.status) {
            try await bootstrap(plist: plist)
            return
        }
        throw AgentControlError.launchctlFailed(status: result.status, output: result.output)
    }

    private static func bootstrap(plist: URL) async throws {
        let args = bootstrapArguments(plistPath: plist.path)
        let first = try await runLaunchctl(args)
        if first.status == 0 { return }
        // launchd may return EIO (5) briefly right after bootout; wait and retry once.
        if first.status == 5 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let retry = try await runLaunchctl(args)
            if retry.status == 0 { return }
            if await isServiceLoaded() { return }
            throw AgentControlError.launchctlFailed(status: retry.status, output: retry.output)
        }
        throw AgentControlError.launchctlFailed(status: first.status, output: first.output)
    }

    private static func runLaunchctl(_ arguments: [String]) async throws -> ProcessResult {
        try await runExecutable("/bin/launchctl", arguments: arguments)
    }

    private static func runExecutable(_ path: String, arguments: [String]) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { throw AgentControlError.cannotRun(error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ProcessResult(status: process.terminationStatus, output: text)
        }.value
    }
}
