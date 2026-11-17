import SwiftUI

/// Content of the panel window: the live panel plus a toolbar with the window options.
struct PanelRootView: View {
    let model: SecureWebViewModel
    @ObservedObject var preferences: PanelPreferences
    @State private var showOpacity = false

    var body: some View {
        SecureWebView(model: model)
            .frame(minWidth: 480, minHeight: 240)
            .toolbar {
                ToolbarItemGroup {
                    Toggle(isOn: $preferences.alwaysOnTop) {
                        Label("Luôn ở trên cùng", systemImage: preferences.alwaysOnTop ? "pin.fill" : "pin")
                    }
                    .help("Luôn ở trên cùng")
                    Button { showOpacity.toggle() } label: {
                        Label("Độ mờ", systemImage: "circle.lefthalf.filled")
                    }
                    .help("Độ mờ cửa sổ")
                    .popover(isPresented: $showOpacity) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Độ mờ: \(Int((preferences.opacity * 100).rounded()))%").font(.callout)
                            Slider(value: $preferences.opacity, in: PanelPreferences.opacityRange)
                                .frame(width: 200)
                        }
                        .padding(14)
                    }
                    Button { model.reload() } label: { Label("Tải lại", systemImage: "arrow.clockwise") }
                        .help("Tải lại bảng điều khiển")
                }
            }
    }
}
