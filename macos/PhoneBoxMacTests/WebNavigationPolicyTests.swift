import XCTest
@testable import PhoneBox

final class WebNavigationPolicyTests: XCTestCase {
    private func decide(_ text: String) -> NavigationDecision { WebNavigationPolicy.decide(for: URL(string: text)) }

    func testAgentOriginIsAllowed() {
        XCTAssertEqual(decide("http://127.0.0.1:8765/"), .allow)
        XCTAssertEqual(decide("http://127.0.0.1:8765/panel/?x=1#a"), .allow)
        XCTAssertEqual(decide("http://127.0.0.1:8765/#general"), .allow)
        XCTAssertEqual(decide("about:blank"), .allow)
    }

    func testLookalikeOriginsAreNotAllowed() {
        XCTAssertEqual(decide("http://127.0.0.1:8766/"), .openExternally)
        XCTAssertEqual(decide("http://127.0.0.1/"), .openExternally)
        XCTAssertEqual(decide("https://127.0.0.1:8765/"), .openExternally)
        XCTAssertEqual(decide("http://localhost:8765/"), .openExternally)
        XCTAssertEqual(decide("http://127.0.0.1.evil.com:8765/"), .openExternally)
        XCTAssertEqual(decide("http://127.0.0.1:8765@evil.com/"), .openExternally)
        XCTAssertEqual(decide("http://user:pw@127.0.0.1:8765/"), .openExternally)
    }

    func testExternalWebLinksGoToBrowser() {
        XCTAssertEqual(decide("https://github.com/x/y"), .openExternally)
        XCTAssertEqual(decide("mailto:a@b.c"), .openExternally)
    }

    func testOtherSchemesAreBlocked() {
        XCTAssertEqual(decide("file:///etc/passwd"), .block)
        XCTAssertEqual(decide("javascript:alert(1)"), .block)
        XCTAssertEqual(decide("data:text/html,hi"), .block)
        XCTAssertEqual(WebNavigationPolicy.decide(for: nil), .block)
    }
}
