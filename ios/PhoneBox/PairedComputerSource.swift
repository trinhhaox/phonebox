import Foundation

/// What the bridge needs from pairing: the list, the route, and switching or forgetting a computer. `AgentLink` already
/// does all of it; the protocol keeps the bridge testable and independent of how phase 04 adds computers.
protocol PairedComputerSource: Sendable {
    var computers: PairedState { get async }
    var route: AgentRoute { get async }
    func select(_ id: String) async throws
    func forget(_ id: String) async throws
}

extension AgentLink: PairedComputerSource {}

extension Notification.Name {
    /// Post after the paired list changed outside the bridge (pairing finished, a computer was removed in the native menu)
    /// so the panel's `pcs()` list refreshes.
    static let phoneBoxComputersChanged = Notification.Name("vn.xox.phonebox.computersChanged")
}
