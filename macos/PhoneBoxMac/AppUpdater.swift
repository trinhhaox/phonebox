import AppKit
import Foundation

@MainActor
final class AppUpdater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease)
        case verifying(AppRelease)
        case readyToInstall(AppRelease, stagedApp: URL, stagingRoot: URL)
        case installing(AppRelease)
        case failed(String)
    }

    private enum Keys {
        static let autoUpdate = "app.autoUpdate"
    }

    static let checkInterval: TimeInterval = 6 * 60 * 60
    static let initialDelayNanoseconds: UInt64 = 15_000_000_000

    @Published var autoUpdateEnabled: Bool {
        didSet { defaults.set(autoUpdateEnabled, forKey: Keys.autoUpdate) }
    }
    @Published private(set) var state: State = .idle

    let currentVersion: AppVersion
    private let defaults: UserDefaults
    private let bundleURL: URL
    private let redirectDelegate: PinnedRedirectDelegate
    private let session: URLSession

    private var cachedETag: String?
    private var cachedLatestRelease: AppRelease?
    private var failedAutoUpdateVersion: AppVersion?
    private var checkTimer: Timer?
    private var initialCheckTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?
    private var hasOpenWindows: () -> Bool = { false }
    private var terminateApp: () -> Void = { NSApp.terminate(nil) }

    init(
        currentVersion: AppVersion = .current(),
        bundleURL: URL = Bundle.main.bundleURL,
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = currentVersion
        self.bundleURL = bundleURL
        self.defaults = defaults
        self.autoUpdateEnabled = defaults.object(forKey: Keys.autoUpdate) as? Bool ?? true

        let delegate = PinnedRedirectDelegate()
        self.redirectDelegate = delegate
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    var canInstallInPlace: Bool {
        AppUpdatePolicy.canReplaceInPlace(bundleURL: bundleURL)
    }

    func start(
        enabled: Bool = true,
        hasOpenWindows: @escaping () -> Bool,
        terminateApp: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.hasOpenWindows = hasOpenWindows
        self.terminateApp = terminateApp
        guard enabled, checkTimer == nil else { return }

        AppUpdateInstaller.cleanupOldStaging()

        initialCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.initialDelayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.checkNow(userInitiated: false)
        }

        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow(userInitiated: false) }
        }
    }

    func checkNow(userInitiated: Bool = true) {
        switch state {
        case .checking, .downloading, .verifying, .installing:
            return
        case .readyToInstall where !userInitiated:
            return
        default:
            break
        }

        if userInitiated {
            failedAutoUpdateVersion = nil
        }

        let previousState = state
        if userInitiated || shouldShowCheckingState(previousState) {
            state = .checking
        }

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let latest = try await self.fetchLatestRelease()
                guard let latest, latest.version > self.currentVersion else {
                    self.clearStagedIfPresent(from: previousState)
                    self.state = userInitiated ? .upToDate : .idle
                    return
                }

                if case let .readyToInstall(stagedRelease, _, _) = previousState,
                   stagedRelease.version == latest.version {
                    self.state = previousState
                    return
                }

                self.clearStagedIfPresent(from: previousState)
                self.state = .available(latest)

                if !userInitiated && self.autoUpdateEnabled && self.canInstallInPlace
                    && self.failedAutoUpdateVersion != latest.version {
                    self.downloadAndStage(release: latest, applyImmediatelyIfIdle: true)
                }
            } catch {
                if userInitiated {
                    self.state = .failed(error.localizedDescription)
                } else {
                    self.state = previousState == .idle || self.shouldShowCheckingState(previousState) ? .idle : previousState
                }
            }
        }
    }

    func installAvailable() {
        switch state {
        case .readyToInstall:
            applyStagedUpdate()
        case let .available(release):
            guard canInstallInPlace else {
                NSWorkspace.shared.open(release.htmlURL)
                return
            }
            downloadAndStage(release: release, applyImmediatelyIfIdle: false, forceImmediateInstall: true)
        default:
            checkNow(userInitiated: true)
        }
    }

    func applyStagedUpdate() {
        guard case let .readyToInstall(release, stagedApp, stagingRoot) = state else { return }
        state = .installing(release)
        do {
            try AppUpdateInstaller.launchSwapHelper(targetApp: bundleURL, stagedApp: stagedApp, stagingRoot: stagingRoot)
            terminateApp()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func handleAllWindowsClosed() {
        guard autoUpdateEnabled, case .readyToInstall = state, canInstallInPlace else { return }
        applyStagedUpdate()
    }

    private func shouldShowCheckingState(_ current: State) -> Bool {
        switch current {
        case .idle, .upToDate, .failed:
            return true
        default:
            return false
        }
    }

    private func clearStagedIfPresent(from previous: State) {
        if case let .readyToInstall(_, _, stagingRoot) = previous {
            try? FileManager.default.removeItem(at: stagingRoot)
        }
    }

    private func fetchLatestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: AppUpdatePolicy.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PhoneBoxMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let cachedETag {
            request.setValue(cachedETag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        if http.statusCode == 304 {
            return cachedLatestRelease
        }
        guard http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse
        }
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            cachedETag = etag
        }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let latest = AppUpdatePolicy.selectLatestRelease(from: releases)
        cachedLatestRelease = latest
        return latest
    }

    private func downloadAndStage(release: AppRelease, applyImmediatelyIfIdle: Bool, forceImmediateInstall: Bool = false) {
        clearStagedIfPresent(from: state)
        state = .downloading(release)

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let staged = try await AppUpdateInstaller.downloadAndVerify(
                    release: release,
                    currentVersion: self.currentVersion,
                    session: self.session,
                    onVerifying: { [weak self] in
                        Task { @MainActor in
                            guard let self, case .downloading = self.state else { return }
                            self.state = .verifying(release)
                        }
                    }
                )
                self.state = .readyToInstall(release, stagedApp: staged.stagedApp, stagingRoot: staged.stagingRoot)
                if forceImmediateInstall || (applyImmediatelyIfIdle && !self.hasOpenWindows()) {
                    self.applyStagedUpdate()
                }
            } catch {
                if forceImmediateInstall {
                    self.state = .failed(error.localizedDescription)
                } else {
                    self.failedAutoUpdateVersion = release.version
                    self.state = .available(release)
                }
            }
        }
    }
}
