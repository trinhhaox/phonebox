import XCTest
@testable import PhoneBox

final class ManualHostTests: XCTestCase {
    func testAcceptsTailscaleIpAndNames() {
        XCTAssertEqual(ManualHost.validate(" 100.76.38.107 \n"), .success("100.76.38.107"))
        XCTAssertEqual(ManualHost.validate("My-Mac.tail1234.ts.net"), .success("my-mac.tail1234.ts.net"))
        XCTAssertEqual(ManualHost.validate("mac"), .success("mac"))
        XCTAssertEqual(ManualHost.validate("192.168.1.24"), .success("192.168.1.24"))
    }

    func testEmpty() {
        XCTAssertEqual(ManualHost.validate("   "), .failure(.empty))
    }

    func testRefusesPublicIpv4() {
        XCTAssertEqual(ManualHost.validate("8.8.8.8"), .failure(.publicAddress))
        XCTAssertEqual(ManualHost.validate("100.128.0.1"), .failure(.publicAddress))
        XCTAssertEqual(ManualHost.validate("10.0.0.256"), .failure(.publicAddress))
    }

    func testRefusesUrlsPortsPathsAndJunk() {
        for bad in ["https://100.76.38.107", "100.76.38.107:8766", "mac/api", "mac name", "-mac.ts.net", "mac-.ts.net",
                    "mac..ts.net", ".mac", "mac.", "mac_name", "[::1]", "mac@host", "tên-máy"] {
            XCTAssertEqual(ManualHost.validate(bad), .failure(.malformed), bad)
        }
        XCTAssertEqual(ManualHost.validate(String(repeating: "a", count: 64)), .failure(.malformed), "label over 63 chars")
        XCTAssertEqual(ManualHost.validate(Array(repeating: "abcdefghi", count: 30).joined(separator: ".")), .failure(.malformed), "over 253 chars")
    }

    func testStoreAddsDeduplicatesAndSurvivesRepair() {
        var state = PairedState()
        let pc = PairedComputer(id: "a", name: "Mac", hosts: ["192.168.1.2"], port: 8766, token: "t")
        state.upsert(pc)
        XCTAssertTrue(state.addExtraHost("100.76.38.107", to: "a"))
        XCTAssertTrue(state.addExtraHost("100.76.38.107", to: "a"))
        XCTAssertTrue(state.addExtraHost("192.168.1.2", to: "a"), "already a paired host")
        XCTAssertFalse(state.addExtraHost("1.2.3.4", to: "missing"))
        XCTAssertEqual(state.computers[0].extraHosts, ["100.76.38.107"])
        state.upsert(PairedComputer(id: "a", name: "Mac", hosts: ["192.168.1.9"], port: 8766, token: "t2"))
        XCTAssertEqual(state.computers[0].allHosts, ["192.168.1.9", "100.76.38.107"])
        state.removeExtraHost("100.76.38.107", from: "a")
        XCTAssertEqual(state.computers[0].allHosts, ["192.168.1.9"])
    }

    func testStateSavedBeforeManualHostsStillDecodes() throws {
        let json = #"{"computers":[{"id":"a","name":"Mac","hosts":["10.0.0.1"],"port":8766,"token":"t"}],"activeId":"a"}"#
        let state = try JSONDecoder().decode(PairedState.self, from: Data(json.utf8))
        XCTAssertEqual(state.computers[0].extraHosts, [])
    }
}
