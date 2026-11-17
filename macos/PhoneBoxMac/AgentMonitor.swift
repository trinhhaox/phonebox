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
    @Published private(set) var status: AgentStatus = .checking
    @Published private(set) var phones: [PhoneRecord] = []
    @Published private(set) var restarting = false
    @Published private(set) var lastError: String?

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

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.poll() }
    }

    func restart() {
        guard !restarting else { return }
        restarting = true
        lastError = nil
        Task { [weak self] in
            do { try await AgentControl.restartAgent() } catch { self?.lastError = error.localizedDescription }
            // the agent needs a few seconds to come back; poll again shortly after
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.restarting = false
            self?.refresh()
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
