import XCTest
@testable import PhoneBox

final class AgentModelsTests: XCTestCase {
    func testInfoDecodesCapturedResponse() throws {
        let info = try JSONDecoder().decode(AgentInfo.self, from: AgentFixtures.info)
        XCTAssertEqual(info.version, "0.9.18")
        XCTAssertTrue(info.connected)
        XCTAssertEqual(info.via, "USB")
        XCTAssertEqual(info.devices.count, 1)
        XCTAssertTrue(info.appMissing.isEmpty)
    }

    func testInfoDecodesDisconnectedWithUnknownFieldShapes() throws {
        let info = try JSONDecoder().decode(AgentInfo.self, from: AgentFixtures.infoDisconnected)
        XCTAssertFalse(info.connected)
        XCTAssertNil(info.via)
        XCTAssertEqual(info.appMissing, ["adb-SERIAL"])
    }

    func testInfoRejectsPayloadWithoutVersion() {
        XCTAssertThrowsError(try JSONDecoder().decode(AgentInfo.self, from: Data(#"{"connected":true}"#.utf8)))
    }

    func testPhonesDecodeAndPreferUserName() throws {
        let phones = try JSONDecoder().decode([PhoneRecord].self, from: AgentFixtures.phones)
        XCTAssertEqual(phones.count, 2)
        XCTAssertEqual(phones[0].displayName, "Jambo Technology JP1")
        XCTAssertEqual(phones[1].displayName, "iPhone của tôi")
        XCTAssertEqual(phones[1].via, "Wi-Fi")
    }

    func testPhoneWithoutNameOrModelGetsIdFallback() throws {
        let phones = try JSONDecoder().decode([PhoneRecord].self, from: Data(#"[{"id":"abcdef123456"}]"#.utf8))
        XCTAssertEqual(phones[0].displayName, "Điện thoại abcdef")
        XCTAssertFalse(phones[0].isRecent())
    }

    func testSummaryListsRecentPhonesOnly() throws {
        let info = try JSONDecoder().decode(AgentInfo.self, from: AgentFixtures.info)
        let phones = try JSONDecoder().decode([PhoneRecord].self, from: AgentFixtures.phones)
        let now = Date(timeIntervalSince1970: 1_794_933_610)
        XCTAssertEqual(PhoneSummary.lines(info: info, phones: phones, now: now),
                       ["Jambo Technology JP1 · USB", "iPhone của tôi · Wi-Fi"])
        let later = Date(timeIntervalSince1970: 1_794_933_610 + 3600)
        XCTAssertEqual(PhoneSummary.lines(info: info, phones: phones, now: later), ["Điện thoại · USB"])
    }

    func testSummaryEmptyWhenNothingConnected() throws {
        let info = try JSONDecoder().decode(AgentInfo.self, from: AgentFixtures.infoDisconnected)
        XCTAssertEqual(PhoneSummary.lines(info: info, phones: [], now: Date()), [])
    }
}
