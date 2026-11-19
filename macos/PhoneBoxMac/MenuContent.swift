import AppKit
import SwiftUI

/// The menu bar menu (native NSMenu style, so it feels like any other macOS menu).
struct MenuContent: View {
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var preferences: PanelPreferences
    @ObservedObject var updater: AppUpdater
    let windows: WindowCoordinator

    private var installed: Bool { monitor.status != .notInstalled }

    var body: some View {
        statusSection
        Divider()
        Button("Mở bảng điều khiển") { windows.showPanel() }.disabled(!installed)
        Toggle("Bảng luôn ở trên cùng", isOn: $preferences.alwaysOnTop)
        Button("Mở cài đặt…") { windows.showSettings() }
            .keyboardShortcut(",").disabled(!installed)
        Button("Ghép đôi điện thoại qua Wi-Fi…") { windows.showSettings(pairing: true) }.disabled(!installed)
        Divider()
        if installed {
            if monitor.status == .stopped {
                Button(monitor.pendingAction == .starting ? "Đang khởi động agent…" : "Khởi động PhoneBox agent") {
                    monitor.startAgent()
                }
                .disabled(monitor.isBusy)
                .help("Khởi động tác vụ nền \(AgentInstallation.launchdLabel)")
            } else {
                Button(monitor.pendingAction == .restarting ? "Đang khởi động lại…" : "Khởi động lại agent") {
                    monitor.restart()
                }
                .disabled(monitor.isBusy)
                .help("Chạy launchctl kickstart -k cho tác vụ \(AgentInstallation.launchdLabel)")

                Button(monitor.pendingAction == .stopping ? "Đang dừng agent…" : "Dừng agent") {
                    monitor.stop()
                }
                .disabled(monitor.isBusy)
                .help("Dừng tác vụ nền \(AgentInstallation.launchdLabel) bằng launchctl bootout")
            }
        }
        Toggle("Mở khi đăng nhập", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
            .help("Chỉ áp dụng cho ứng dụng menu này; agent tự chạy theo launchd")
        if let message = launchAtLogin.errorMessage { Text(message) }
        Divider()
        Toggle("Tự động cập nhật", isOn: $updater.autoUpdateEnabled)
            .help("Tự động tải, xác minh chữ ký và cập nhật ứng dụng Mac khi có bản mới")
        updateSection
        Divider()
        if installed {
            Button("Chỉ thoát ứng dụng menu") { NSApp.terminate(nil) }
                .help("Đóng biểu tượng menu này; PhoneBox agent vẫn tiếp tục chạy nền")
            Button(monitor.pendingAction == .quitting ? "Đang tắt PhoneBox…" : "Tắt hẳn PhoneBox") {
                monitor.quitCompletely(windows: windows)
            }
            .keyboardShortcut("q")
            .disabled(monitor.isBusy)
            .help("Dừng hẳn PhoneBox agent chạy nền và thoát hoàn toàn ứng dụng")
        } else {
            Button("Thoát PhoneBox") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    @ViewBuilder private var updateSection: some View {
        switch updater.state {
        case .idle:
            Button("Kiểm tra cập nhật…") { updater.checkNow(userInitiated: true) }
        case .checking:
            Button("Đang kiểm tra cập nhật…") {}.disabled(true)
        case .upToDate:
            Button("Đã là bản mới nhất (v\(updater.currentVersion)) — Kiểm tra lại") {
                updater.checkNow(userInitiated: true)
            }
        case let .available(rel):
            Button(updater.canInstallInPlace ? "Cập nhật lên v\(rel.version)…" : "Tải bản mới v\(rel.version)…") {
                updater.installAvailable()
            }
        case let .downloading(rel):
            Button("Đang tải bản v\(rel.version)…") {}.disabled(true)
        case let .verifying(rel):
            Button("Đang xác minh bản v\(rel.version)…") {}.disabled(true)
        case let .readyToInstall(rel, _, _):
            Button("Khởi động lại để cập nhật v\(rel.version)") { updater.applyStagedUpdate() }
        case let .installing(rel):
            Button("Đang cài đặt v\(rel.version)…") {}.disabled(true)
        case let .failed(message):
            Text("Lỗi cập nhật: \(message)")
            Button("Thử kiểm tra cập nhật lại") { updater.checkNow(userInitiated: true) }
        }
    }

    @ViewBuilder private var statusSection: some View {
        switch monitor.status {
        case .checking:
            Text("Đang kiểm tra agent…")
        case .notInstalled:
            Text("Chưa cài PhoneBox agent")
            Text("Hãy chạy setup.sh trong thư mục dự án, hoặc cài ngay bên dưới")
            Button("Cài đặt PhoneBox agent…") { windows.showInstaller { monitor.refresh() } }
        case .stopped:
            Text("Agent đã dừng")
            if let error = monitor.lastError { Text(error) }
        case let .running(info):
            Text("PhoneBox agent \(info.version) đang chạy")
            let lines = PhoneSummary.lines(info: info, phones: monitor.phones)
            if lines.isEmpty {
                Text("Chưa có điện thoại kết nối")
            } else {
                ForEach(lines, id: \.self) { Text("📱 \($0)") }
            }
            if !info.appMissing.isEmpty { Text("Điện thoại chưa cài ứng dụng PhoneBox") }
        }
        if let error = monitor.lastError, monitor.status != .stopped { Text(error) }
    }
}
