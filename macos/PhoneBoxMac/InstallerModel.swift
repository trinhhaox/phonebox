import Foundation

@MainActor
final class InstallerModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lines: [String] = []
    private var task: Task<Void, Never>?
    private let onSuccess: () -> Void
    static let maxLines = 500

    init(onSuccess: @escaping () -> Void) { self.onSuccess = onSuccess }

    func start() {
        guard state != .running else { return }
        lines = []
        state = .running
        task = Task { [weak self] in await self?.execute() }
    }

    func cancel() {
        task?.cancel()
        if state == .running { state = .failed("Đã hủy cài đặt") }
    }

    private func execute() async {
        do {
            let script = try AgentInstaller.bundledScript()
            for try await event in AgentInstaller.run(AgentInstaller.command(script: script)) {
                switch event {
                case let .line(text):
                    lines.append(text)
                    if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
                case let .finished(status):
                    state = status == 0 ? .succeeded : .failed("setup.sh kết thúc với mã lỗi \(status)")
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
        if state == .succeeded { onSuccess() }
    }
}
