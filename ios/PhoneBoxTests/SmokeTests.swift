import XCTest
@testable import PhoneBox

final class SmokeTests: XCTestCase {
    func testPanelAssetsAreBundled() throws {
        let www = try XCTUnwrap(Bundle.main.url(forResource: "www", withExtension: nil), "www folder reference missing")
        for file in ["index.html", "main.js", "widgets/stack.js"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: www.appendingPathComponent(file).path), "\(file) missing")
        }
    }

    func testPanelVersionKeyIsSet() {
        let v = Bundle.main.object(forInfoDictionaryKey: "PhoneBoxPanelVersion") as? String
        XCTAssertEqual(v, "0.9.16")
    }
}
