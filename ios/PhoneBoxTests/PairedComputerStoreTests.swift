import XCTest
@testable import PhoneBox

final class PairedComputerStoreTests: XCTestCase {
    private var keychain = KeychainStore(service: "phonebox.tests.\(UUID().uuidString)")
    private func pc(_ id: String, name: String = "pc", token: String = "t") -> PairedComputer {
        PairedComputer(id: id, name: name, hosts: ["192.168.1.2"], port: 8766, token: token)
    }

    override func tearDown() { try? keychain.delete("state"); try? keychain.delete("k") }

    func testKeychainRoundTripUpdateAndDelete() throws {
        XCTAssertNil(try keychain.read("k"))
        try keychain.write("k", Data("one".utf8))
        XCTAssertEqual(try keychain.read("k"), Data("one".utf8))
        try keychain.write("k", Data("two".utf8))
        XCTAssertEqual(try keychain.read("k"), Data("two".utf8))
        try keychain.delete("k")
        XCTAssertNil(try keychain.read("k"))
        XCTAssertNoThrow(try keychain.delete("k"))
    }

    func testStoreRoundTrip() throws {
        let store = PairedComputerStore(keychain: keychain)
        XCTAssertEqual(store.load(), PairedState())
        var s = PairedState()
        s.upsert(pc("a")); s.upsert(pc("b"))
        try store.save(s)
        XCTAssertEqual(store.load(), s)
        XCTAssertEqual(store.load().active?.id, "b")
    }

    func testCorruptJSONLoadsEmpty() throws {
        try keychain.write("state", Data("{not json".utf8))
        XCTAssertEqual(PairedComputerStore(keychain: keychain).load(), PairedState())
    }

    func testUpsertReplacesSameIdOnly() {
        var s = PairedState()
        s.upsert(pc("a", name: "old")); s.upsert(pc("b", name: "old"))
        s.upsert(pc("a", name: "new", token: "t2"))
        XCTAssertEqual(s.computers.map(\.id).sorted(), ["a", "b"])
        XCTAssertEqual(s.active?.token, "t2")
    }

    func testForgetActiveFallsBackToFirst() {
        var s = PairedState()
        s.upsert(pc("a")); s.upsert(pc("b"))
        s.forget("b")
        XCTAssertEqual(s.active?.id, "a")
        s.forget("a")
        XCTAssertNil(s.active)
        XCTAssertFalse(s.select("zzz"))
    }
}
