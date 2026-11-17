import SwiftUI

extension PairedComputer: Identifiable {}

/// Native menu opened by a two-finger long press on the panel (and automatically while no computer is paired).
struct NativeMenuView: View {
    @ObservedObject var model: PairingModel
    let panelVersion: String
    @State private var addressFor: PairedComputer?

    var body: some View {
        NavigationStack {
            List {
                if model.computers.computers.isEmpty { onboarding }
                else { computersSection }
                Section {
                    Button { model.showScanner = true } label: { Label("Quét mã QR để ghép nối", systemImage: "qrcode.viewfinder") }
                }
                Section("Thông tin") {
                    LabeledContent("Phiên bản bảng điều khiển", value: panelVersion)
                    Text("Lần đầu kết nối, iOS sẽ hỏi quyền Mạng cục bộ. Hãy chọn Cho phép để PhoneBox thấy máy tính của bạn.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("PhoneBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { model.showMenu = false } } }
        }
        .sheet(item: $addressFor) { pc in ManualHostView(model: model, computerId: pc.id) }
        .fullScreenCover(isPresented: $model.showScanner) { scanner }
    }

    private var onboarding: some View {
        Section("Chưa ghép nối") {
            Text("Mở Cài đặt PhoneBox trên máy tính, vào Chung, Wi-Fi và Tailscale, chọn Ghép nối điện thoại qua Wi-Fi, rồi quét mã QR hiện ra.")
        }
    }

    private var computersSection: some View {
        Section("Máy tính đã ghép nối") {
            ForEach(model.computers.computers) { pc in
                let isActive = pc.id == model.computers.active?.id
                HStack {
                    Button { model.select(pc.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pc.name).foregroundStyle(.primary)
                            Text(pc.allHosts.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if isActive { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    Button { addressFor = pc } label: { Image(systemName: "plus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Thêm địa chỉ cho \(pc.name)")
                }
                .swipeActions { Button("Quên", role: .destructive) { model.forget(pc.id) } }
            }
        }
    }

    private var scanner: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerView { model.offer(text: $0) }.ignoresSafeArea()
            Button("Đóng") { model.showScanner = false }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }
}
