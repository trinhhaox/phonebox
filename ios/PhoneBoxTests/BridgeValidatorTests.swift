import XCTest
@testable import PhoneBox

final class BridgeValidatorTests: XCTestCase {
    private let key = "11111111-2222-3333-4444-555555555555"
    private let id = String(repeating: "ab", count: 32)

    private func parse(_ method: String, _ args: [Any] = [], key: String? = nil, main: Bool = true,
                       scheme: String = "pbapp", host: String = "panel") -> Result<BridgeCommand, BridgeRejection> {
        BridgeValidator.parse(isMainFrame: main, scheme: scheme, host: host, expectedKey: self.key,
                              body: ["k": key ?? self.key, "m": method, "a": args] as [String: Any])
    }

    func testAcceptsKnownMethods() {
        XCTAssertEqual(parse("haptic"), .success(.haptic))
        XCTAssertEqual(parse("buzz", ["0,100,50,200"]), .success(.buzz([0, 100, 50, 200])))
        XCTAssertEqual(parse("setOrientation", ["portrait"]), .success(.setOrientation(.portrait)))
        XCTAssertEqual(parse("selectPc", [id]), .success(.selectPc(id)))
        XCTAssertEqual(parse("forgetPc", [id]), .success(.forgetPc(id)))
        XCTAssertEqual(parse("listen", [3, "vi-VN", false]), .success(.listen(id: 3, lang: "vi-VN", offline: false)))
        XCTAssertEqual(parse("stopListening", [3]), .success(.stopListening(3)))
        XCTAssertEqual(parse("cancelListening", [3]), .success(.cancelListening(3)))
    }

    func testRejectsWrongCaller() {
        XCTAssertEqual(parse("haptic", main: false), .failure(.notMainFrame))
        XCTAssertEqual(parse("haptic", scheme: "https"), .failure(.wrongOrigin))
        XCTAssertEqual(parse("haptic", host: "evil"), .failure(.wrongOrigin))
        XCTAssertEqual(parse("haptic", key: "guess"), .failure(.badKey))
        XCTAssertEqual(parse("haptic", key: ""), .failure(.badKey))
    }

    func testRejectsMalformedBodyAndUnknownMethods() {
        let notADict = BridgeValidator.parse(isMainFrame: true, scheme: "pbapp", host: "panel", expectedKey: key, body: "haptic")
        XCTAssertEqual(notADict, .failure(.malformed))
        XCTAssertEqual(parse("setVolumeKeys", [true]), .failure(.unknownMethod))
        XCTAssertEqual(parse("eval", ["alert(1)"]), .failure(.unknownMethod))
    }

    func testBrightnessRules() {
        XCTAssertEqual(parse("setBrightness", [0.4]), .success(.setBrightness(0.4)))
        XCTAssertEqual(parse("setBrightness", [7]), .success(.setBrightness(1)))
        XCTAssertEqual(parse("setBrightness", [-3]), .success(.setBrightness(-1)))
        XCTAssertEqual(parse("setBrightness", ["0.4"]), .failure(.malformed))
        XCTAssertEqual(parse("setBrightness", [true]), .failure(.malformed))
        XCTAssertEqual(parse("setBrightness", [Double.nan]), .failure(.malformed))
        XCTAssertEqual(parse("setBrightness"), .failure(.malformed))
    }

    func testBuzzPatternLimits() {
        XCTAssertNil(BridgeValidator.pattern(""))
        XCTAssertNil(BridgeValidator.pattern("0,5001"))
        XCTAssertNil(BridgeValidator.pattern("0,-5"))
        XCTAssertNil(BridgeValidator.pattern(Array(repeating: "10", count: 33).joined(separator: ",")))
        XCTAssertEqual(BridgeValidator.pattern("0, x, 20"), [0, 20])
        XCTAssertEqual(BridgeValidator.pattern(Array(repeating: "10", count: 32).joined(separator: ","))?.count, 32)
        XCTAssertEqual(parse("buzz", [42]), .failure(.malformed))
    }

    func testComputerIdMustBeLowercaseHexSha256() {
        XCTAssertEqual(parse("selectPc", ["abc"]), .failure(.malformed))
        XCTAssertEqual(parse("selectPc", [String(repeating: "AB", count: 32)]), .failure(.malformed))
        XCTAssertEqual(parse("forgetPc", [String(repeating: "g", count: 64)]), .failure(.malformed))
    }

    func testListenArguments() {
        XCTAssertEqual(parse("listen", [1, "vi-VN; drop", true]), .success(.listen(id: 1, lang: "vi-VNdrop", offline: true)))
        XCTAssertEqual(BridgeValidator.sanitizeLanguage(String(repeating: "a", count: 40)).count, 20)
        XCTAssertEqual(parse("listen", [0, "en", false]), .failure(.malformed))
        XCTAssertEqual(parse("listen", [1.5, "en", false]), .failure(.malformed))
        XCTAssertEqual(parse("listen", [1, "en"]), .failure(.malformed))
        XCTAssertEqual(parse("listen", [1, "en", "yes"]), .failure(.malformed))
        XCTAssertEqual(parse("stopListening", [-1]), .failure(.malformed))
    }
}
