import Foundation
import ServiceManagement

/// "Open at login" for THIS menu app (not the agent, which has its own launchd job).
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "Không đổi được “Mở khi đăng nhập”: \(error.localizedDescription)"
        }
        refresh()
    }
}
