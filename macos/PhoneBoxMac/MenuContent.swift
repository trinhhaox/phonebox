import AppKit
import SwiftUI

/// The menu bar menu (native NSMenu style, so it feels like any other macOS menu).
struct MenuContent: View {
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var preferences: PanelPreferences
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
        Button(monitor.restarting ? "Đang khởi động lại…" : "Khởi động lại PhoneBox") { monitor.restart() }
            .disabled(!installed || monitor.restarting)
            .help("Chạy launchctl kickstart -k cho tác vụ \(AgentInstallation.launchdLabel)")
        Toggle("Mở khi đăng nhập", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
            .help("Chỉ áp dụng cho ứng dụng menu này; agent tự chạy theo launchd")
        if let message = launchAtLogin.errorMessage { Text(message) }
        Divider()
        Text("Thoát chỉ đóng ứng dụng menu, agent vẫn chạy nền")
        Button("Thoát") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .help("Chỉ thoát ứng dụng menu này; agent PhoneBox vẫn tiếp tục chạy")
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
            Text("Agent không chạy")
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
