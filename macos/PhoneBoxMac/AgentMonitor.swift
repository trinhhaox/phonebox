import AppKit
import Foundation

enum AgentStatus: Equatable {
    case checking
    case notInstalled
    case stopped
    case running(AgentInfo)
}

/// Polls the local agent at a low rate (and on demand) and publishes what the menu shows.
@MainActor
final class AgentMonitor: ObservableObject {
    enum PendingAction: Equatable {
        case starting
        case restarting
        case stopping
        case quitting
    }

    @Published private(set) var status: AgentStatus = .checking
    @Published private(set) var phones: [PhoneRecord] = []
    @Published private(set) var pendingAction: PendingAction?
    @Published private(set) var lastError: String?

    var isBusy: Bool { pendingAction != nil }
    var restarting: Bool { pendingAction == .restarting }

    private let installation: AgentInstallation
    private let session: URLSession
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    static let pollInterval: TimeInterval = 8

    init(installation: AgentInstallation = .standard()) {
        self.installation = installation
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func start(autoBootstrap: Bool = false) {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if autoBootstrap && installation.isInstalled() {
            Task { [weak self] in
                guard let self else { return }
                guard await !AgentControl.isServiceLoaded() else { return }
                guard self.timer != nil, self.pendingAction == nil else { return }
                self.pendingAction = .starting
                self.lastError = nil
                do {
                    try await AgentControl.startAgent(plist: self.installation.launchAgentPlist)
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                } catch {
                    self.lastError = error.localizedDescription
                }
                self.pendingAction = nil
                self.refresh()
            }
        }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.poll() }
    }

    func startAgent() {
        guard pendingAction == nil else { return }
        pendingAction = .starting
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AgentControl.startAgent(plist: self.installation.launchAgentPlist)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            } catch {
                self.lastError = error.localizedDescription
            }
            self.pendingAction = nil
            self.refresh()
        }
    }

    func restart() {
        guard pendingAction == nil else { return }
        pendingAction = .restarting
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AgentControl.restartAgent(plist: self.installation.launchAgentPlist)
                // the agent needs a few seconds to come back; poll again shortly after
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                self.lastError = error.localizedDescription
            }
            self.pendingAction = nil
            self.refresh()
        }
    }

    func stop() {
        guard pendingAction == nil else { return }
        pendingAction = .stopping
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AgentControl.stopAgent()
                self.status = .stopped
                self.phones = []
            } catch {
                self.lastError = error.localizedDescription
            }
            self.pendingAction = nil
            self.refresh()
        }
    }

    func quitCompletely(windows: WindowCoordinator, terminate: @escaping () -> Void = { NSApp.terminate(nil) }) {
        guard pendingAction == nil else { return }
        pendingAction = .quitting
        lastError = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        windows.closeAll()
        Task { [weak self] in
            guard let self else { return }
            do {
                if self.installation.isInstalled() {
                    try await AgentControl.stopAgent()
                }
                terminate()
            } catch {
                self.lastError = error.localizedDescription
                self.pendingAction = nil
                self.start(autoBootstrap: false)
                Self.presentQuitFailureAlert(message: error.localizedDescription, terminate: terminate)
            }
        }
    }

    private static func presentQuitFailureAlert(message: String, terminate: () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Không thể tắt hẳn PhoneBox agent"
        alert.informativeText = message
        alert.addButton(withTitle: "Chỉ thoát ứng dụng menu")
        alert.addButton(withTitle: "Đóng")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            terminate()
        }
    }

    private func poll() async {
        guard installation.isInstalled() else {
            status = .notInstalled
            phones = []
            return
        }
        do {
            let info: AgentInfo = try await fetch(AgentEndpoint.infoURL)
            let list: [PhoneRecord] = try await fetch(AgentEndpoint.phonesURL)
            guard !Task.isCancelled else { return }
            status = .running(info)
            phones = list
            lastError = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as URLError where Self.isConnectionRefused(error) {
            status = .stopped
            phones = []
        } catch {
            // The port answered but the payload was unusable (agent mid-start, wrong version): report, keep "stopped".
            status = .stopped
            phones = []
            lastError = error.localizedDescription
        }
    }

    private static func isConnectionRefused(_ error: URLError) -> Bool {
        [.cannotConnectToHost, .timedOut, .networkConnectionLost, .cannotFindHost].contains(error.code)
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
