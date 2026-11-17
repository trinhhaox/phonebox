import Foundation
import os

/// UI state of pairing and of the native computer menu. Both entry points (QR scanner, `phonebox://pair` link) end in `offer`.
@MainActor
final class PairingModel: ObservableObject {
    private static let log = Logger(subsystem: "vn.xox.phonebox", category: "pairing")
    static let invalidLinkNotice = "Đây không phải mã ghép nối của PhoneBox."

    @Published private(set) var computers = PairedState()
    @Published private(set) var isClaiming = false
    @Published var pending: PairLink?
    @Published var notice: String?
    @Published var showMenu = false
    @Published var showScanner = false

    private let link: AgentLink
    private let claimer: PairingClaim
    private let onChanged: @MainActor () -> Void

    /// `onChanged` runs after the active computer or its addresses changed: restart the stream, reload the panel.
    init(link: AgentLink, claimer: PairingClaim, onChanged: @escaping @MainActor () -> Void) {
        self.link = link
        self.claimer = claimer
        self.onChanged = onChanged
    }

    /// Loads the stored computers and opens the menu (onboarding) when there is none.
    func start() async {
        await refresh()
        if computers.active == nil { showMenu = true }
    }

    /// Reloads the list and tells the panel bridge so its `pcs()` snapshot follows pairing changes.
    func refresh() async {
        computers = await link.computers
        NotificationCenter.default.post(name: .phoneBoxComputersChanged, object: nil)
    }

    /// A scanned QR text. Returns true when it is a pairing link, so the scanner can stop.
    func offer(text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let parsed = PairLink(url: url) else { return false }
        ask(parsed)
        return true
    }

    /// A `phonebox://pair?...` link opened from outside.
    func offer(url: URL) {
        guard let parsed = PairLink(url: url) else {
            if url.scheme?.lowercased() == "phonebox" { notice = Self.invalidLinkNotice }
            return
        }
        ask(parsed)
    }

    private func ask(_ parsed: PairLink) {
        showScanner = false
        showMenu = false
        pending = parsed
    }

    func cancelPending() {
        guard pending != nil else { return } // the alert also reports "dismissed" after Confirm
        pending = nil
        if computers.active == nil { showMenu = true }
    }

    func confirmPending() {
        guard let target = pending, !isClaiming else { return }
        pending = nil
        isClaiming = true
        Task {
            defer { isClaiming = false }
            switch await claimer.claim(target) {
            case .success(let pc):
                do {
                    try await link.upsert(pc)
                    await refresh()
                    onChanged()
                    notice = "Đã ghép nối với \(pc.name)."
                } catch {
                    Self.log.error("saving paired computer failed: \(String(describing: error), privacy: .public)")
                    notice = "Không lưu được thông tin ghép nối vào Keychain. Hãy thử lại."
                }
            case .failure(let error):
                notice = error.message
            }
        }
    }

    func dismissNotice() {
        notice = nil
        if computers.active == nil && pending == nil && !isClaiming { showMenu = true }
    }

    func select(_ id: String) { change { try await $0.select(id) } }
    func forget(_ id: String) { change { try await $0.forget(id) } }
    func removeAddress(_ host: String, from id: String) { change { try await $0.removeExtraHost(host, from: id) } }

    /// Validates and stores a manual address; returns a message for the user when it is refused or cannot be saved.
    func addAddress(_ input: String, to id: String) async -> String? {
        switch ManualHost.validate(input) {
        case .failure(let failure):
            return ManualHost.message(for: failure)
        case .success(let host):
            guard let pc = computers.computers.first(where: { $0.id == id }) else { return "Máy tính này không còn trong danh sách." }
            if pc.extraHosts.count >= ManualHost.maxPerComputer && !pc.extraHosts.contains(host) {
                return "Tối đa \(ManualHost.maxPerComputer) địa chỉ thêm tay cho mỗi máy tính."
            }
            do {
                try await link.addExtraHost(host, to: id)
                await refresh()
                onChanged()
                return nil
            } catch {
                Self.log.error("saving address failed: \(String(describing: error), privacy: .public)")
                return "Không lưu được địa chỉ vào Keychain."
            }
        }
    }

    private func change(_ work: @escaping (AgentLink) async throws -> Void) {
        Task {
            do {
                try await work(link)
                await refresh()
                onChanged()
            } catch {
                Self.log.error("pairing change failed: \(String(describing: error), privacy: .public)")
                notice = "Không lưu được thay đổi vào Keychain."
            }
        }
    }
}
