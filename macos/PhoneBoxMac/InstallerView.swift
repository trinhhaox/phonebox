import SwiftUI

struct InstallerView: View {
    @ObservedObject var model: InstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: model.lines.count) { _, _ in proxy.scrollTo("end") }
            }
            Text("Chạy với quyền của bạn (không dùng sudo). Bản phát hành được tải từ GitHub và kiểm tra SHA-256.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            switch model.state {
            case .idle, .running:
                ProgressView().controlSize(.small)
                Text("Đang cài đặt PhoneBox agent…")
            case .succeeded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Cài đặt thành công. PhoneBox agent đã sẵn sàng.")
            case let .failed(reason):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text("Cài đặt thất bại: \(reason)")
            }
            Spacer()
            if model.state == .running {
                Button("Hủy") { model.cancel() }
            } else if case .failed = model.state {
                Button("Thử lại") { model.start() }
            }
        }
        .font(.headline)
    }
}
