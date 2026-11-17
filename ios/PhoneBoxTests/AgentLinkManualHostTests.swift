import XCTest
@testable import PhoneBox

final class AgentLinkManualHostTests: XCTestCase {
    private let pin = String(repeating: "cd", count: 32)
    private let keychain = KeychainStore(service: "phonebox.tests.\(UUID().uuidString)")

    override func tearDown() { try? keychain.delete("state") }

    func testManualHostIsTriedAfterPairedOnesAndPersisted() async throws {
        ClaimStub.reset { r in
            if r.url?.host == "100.76.38.107" { return (200, Data()) }
            throw URLError(.cannotConnectToHost)
        }
        let store = PairedComputerStore(keychain: keychain)
        let identity = DeviceIdentity(deviceId: "0123456789ab", model: "Apple iPhone15,2", appVersion: "0.9.16")
        let link = AgentLink(store: store, identity: identity) {
            let c = URLSessionConfiguration.ephemeral
            c.protocolClasses = [ClaimStub.self]
            return c
        }
        try await link.upsert(PairedComputer(id: pin, name: "Mac", hosts: ["192.168.1.2"], port: 8766, token: "tok"))
        try await link.addExtraHost("100.76.38.107", to: pin)

        let reply = await link.forward(method: "GET", pathAndQuery: "/api/state")
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(ClaimStub.urls(), ["https://192.168.1.2:8766/api/state", "https://100.76.38.107:8766/api/state"])
        XCTAssertEqual(store.load().computers.first?.extraHosts, ["100.76.38.107"])
    }
}
