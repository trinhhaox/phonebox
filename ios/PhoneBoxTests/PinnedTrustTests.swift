import Security
import XCTest
@testable import PhoneBox

final class PinnedTrustTests: XCTestCase {
    /// Self-signed P-256 test certificate (CN=phonebox-test); fingerprint computed with `shasum -a 256` on its DER.
    private static let derBase64 = "MIIBZDCCAQqgAwIBAgIUe6bojieEA9CK0YODTMJ6sl2DohwwCgYIKoZIzj0EAwIwGDEWMBQGA1UEAwwNcGhvbmVib3gtdGVzdDAeFw0yNjExMTcxMzU5MDdaFw0zNjExMTQxMzU5MDdaMBgxFjAUBgNVBAMMDXBob25lYm94LXRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAR58HGCC1G/Das+o8DjTSmhz6RUNsbpmV9lNuRsMlIjcdl+cBEFpk9wFagA55/4BZHpHKpaztZr7HnMlHTHdFuXozIwMDAdBgNVHQ4EFgQU1Gqh3FBMm14wpmHr84b7WbQb+LowDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiAXs9sdhy4bya8OvfMyZvvpniMb0bJU3BLcbBLOYZDE3AIhAPCXb7b7Rqjx+Z1ivFdmXL8rYmob+iiylweUnn+32Cga"
    private static let expected = "8bd0283828562de36d08bad378699db891522d3f83ec70a53d07bb7559eba578"

    private func certificate() throws -> SecCertificate {
        let der = try XCTUnwrap(Data(base64Encoded: Self.derBase64))
        return try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))
    }

    func testFingerprintMatchesPrecomputedHex() throws {
        XCTAssertEqual(PinnedTrustDelegate.fingerprint(of: try certificate()), Self.expected)
    }

    func testPinCompareIsCaseInsensitiveAndExact() {
        XCTAssertTrue(PinnedTrustDelegate.matches(fingerprint: Self.expected, pin: Self.expected.uppercased()))
        let wrong = String(Self.expected.dropLast()) + "0"
        XCTAssertFalse(PinnedTrustDelegate.matches(fingerprint: Self.expected, pin: wrong))
    }

    func testMalformedPinNeverMatches() {
        XCTAssertFalse(PinnedTrustDelegate.matches(fingerprint: "", pin: ""))
        XCTAssertFalse(PinnedTrustDelegate.matches(fingerprint: "abc", pin: "abc"))
        XCTAssertFalse(PinnedTrustDelegate.matches(fingerprint: Self.expected + "00", pin: Self.expected + "00"))
    }

    func testDeviceIdentityHelpers() {
        XCTAssertEqual(DeviceIdentity.hashedId(from: "x").count, 12)
        XCTAssertEqual(DeviceIdentity.hashedId(from: "x"), DeviceIdentity.hashedId(from: "x"))
        XCTAssertNotEqual(DeviceIdentity.hashedId(from: "x"), DeviceIdentity.hashedId(from: "y"))
        XCTAssertEqual(DeviceIdentity.sanitizedModel("Apple iPhone\u{00E9}15,2\n"), "Apple iPhone15,2")
        XCTAssertEqual(DeviceIdentity.sanitizedModel(String(repeating: "a", count: 99)).count, 40)
    }
}
