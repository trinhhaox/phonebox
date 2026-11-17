import Foundation

/// Where setup.sh puts the agent and its launchd job; injectable so tests can use a temp directory.
struct AgentInstallation: Equatable {
    static let launchdLabel = "net.oxog.phonebox.agent"

    let binary: URL
    let launchAgentPlist: URL

    static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentInstallation {
        AgentInstallation(
            binary: home.appendingPathComponent("Library/Application Support/PhoneBox/app/PhoneBoxAgent"),
            launchAgentPlist: home.appendingPathComponent("Library/LaunchAgents/\(launchdLabel).plist"))
    }

    /// Both the executable and the launchd plist must exist; either one missing means setup.sh was not run (or was undone).
    func isInstalled(fileManager: FileManager = .default) -> Bool {
        fileManager.isExecutableFile(atPath: binary.path) && fileManager.fileExists(atPath: launchAgentPlist.path)
    }
}
