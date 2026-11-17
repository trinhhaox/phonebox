import SwiftUI

/// Adds an address (Tailscale IP or MagicDNS name) to a paired computer. The pinned certificate still has to match.
struct ManualHostView: View {
    @ObservedObject var model: PairingModel
    let computerId: String
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var problem: String?
    @State private var saving = false

    private var computer: PairedComputer? { model.computers.computers.first { $0.id == computerId } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("100.x.y.z hoặc may-tinh.tailnet.ts.net", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit(save)
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Địa chỉ mới cho \(computer?.name ?? "máy tính")")
                } footer: {
                    Text("Dùng khi máy tính ở ngoài mạng nhà, ví dụ địa chỉ Tailscale. Chỉ nhập IP hoặc tên máy, cổng lấy từ lúc ghép nối. Chứng chỉ của máy tính vẫn được kiểm tra.")
                }
                if let extra = computer?.extraHosts, !extra.isEmpty {
                    Section("Địa chỉ đã thêm") {
                        ForEach(extra, id: \.self) { host in
                            Text(host).swipeActions { Button("Xoá", role: .destructive) { model.removeAddress(host, from: computerId) } }
                        }
                    }
                }
            }
            .navigationTitle("Thêm địa chỉ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save).disabled(saving) }
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            problem = await model.addAddress(input, to: computerId)
            saving = false
            if problem == nil { dismiss() }
        }
    }
}
