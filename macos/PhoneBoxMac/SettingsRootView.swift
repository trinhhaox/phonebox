import SwiftUI

/// Content of the settings window: the local agent settings page plus native toolbar actions.
struct SettingsRootView: View {
    let model: SecureWebViewModel
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject var updater: AppUpdater
    let onQuitCompletely: () -> Void
    @State private var confirmQuit = false

    var body: some View {
        VStack(spacing: 0) {
            updateBanner
            SecureWebView(model: model)
        }
        .frame(minWidth: 640, minHeight: 420)
        .toolbar {
            ToolbarItemGroup {
                Button { model.reload() } label: {
                    Label("Tải lại", systemImage: "arrow.clockwise")
                }
                .help("Tải lại trang cài đặt")

                if monitor.status == .stopped {
                    Button { monitor.startAgent() } label: {
                        Label("Khởi động agent", systemImage: "play.fill")
                    }
                    .disabled(monitor.isBusy)
                    .help("Khởi động PhoneBox agent")
                } else {
                    Button { monitor.restart() } label: {
                        Label("Khởi động lại agent", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(monitor.isBusy)
                    .help("Khởi động lại PhoneBox agent")
                }

                Button(role: .destructive) { confirmQuit = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text(monitor.pendingAction == .quitting ? "Đang tắt…" : "Tắt hẳn")
                    }
                    .foregroundStyle(.red)
                }
                .disabled(monitor.isBusy)
                .keyboardShortcut("q", modifiers: .command)
                .help("Dừng hẳn PhoneBox agent chạy nền và thoát hoàn toàn ứng dụng")
            }
        }
        .alert("Tắt hẳn PhoneBox?", isPresented: $confirmQuit) {
            Button("Tắt hẳn", role: .destructive) { onQuitCompletely() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Dừng PhoneBox agent chạy nền và đóng hoàn toàn ứng dụng. Khi mở lại PhoneBox, agent sẽ tự khởi động lại.")
        }
    }

    @ViewBuilder private var updateBanner: some View {
        switch updater.state {
        case let .available(rel):
            bannerRow {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                Text("Đã có PhoneBox v\(rel.version)")
                Spacer()
                Button(updater.canInstallInPlace ? "Cập nhật ngay" : "Mở trang tải") {
                    updater.installAvailable()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case let .downloading(rel):
            bannerRow {
                ProgressView().controlSize(.small)
                Text("Đang tải PhoneBox v\(rel.version)…")
                Spacer()
            }
        case let .verifying(rel):
            bannerRow {
                ProgressView().controlSize(.small)
                Text("Đang xác minh chữ ký PhoneBox v\(rel.version)…")
                Spacer()
            }
        case let .readyToInstall(rel, _, _):
            bannerRow {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                Text("Bản cập nhật v\(rel.version) đã sẵn sàng")
                Spacer()
                Button("Khởi động lại để cập nhật") { updater.applyStagedUpdate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        case let .installing(rel):
            bannerRow {
                ProgressView().controlSize(.small)
                Text("Đang cài đặt PhoneBox v\(rel.version)…")
                Spacer()
            }
        case .idle, .checking, .upToDate, .failed:
            EmptyView()
        }
    }

    private func bannerRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                content()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
    }
}
