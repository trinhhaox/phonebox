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
    /// `launchctl kickstart -k gui/<uid>/<label>`: kills and relaunches the agent job. Arguments are an array, never a shell string.
    static func kickstartArguments(uid: uid_t = getuid(), label: String = AgentInstallation.launchdLabel) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(label)"]
    }

    static func restartAgent() async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = kickstartArguments()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { throw AgentControlError.cannotRun(error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw AgentControlError.launchctlFailed(status: process.terminationStatus, output: text)
            }
        }.value
    }
}
