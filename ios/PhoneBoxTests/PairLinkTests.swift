import XCTest
@testable import PhoneBox

final class PairLinkTests: XCTestCase {
    private let fp = String(repeating: "ab", count: 32)
    private let code = "AbCdEfGhIjKlMnOp"

    private func query(v: String = "1", fp: String? = nil, port: String = "8766", h: String = "192.168.1.24,100.76.38.107",
                       c: String? = nil, pc: String = "My%20Mac") -> String {
        "v=\(v)&pc=\(pc)&fp=\(fp ?? self.fp)&port=\(port)&h=\(h)&c=\(c ?? code)"
    }

    private func parse(_ s: String) -> PairLink? { URL(string: s).flatMap(PairLink.init(url:)) }

    func testHttpsFragmentLink() throws {
        let link = try XCTUnwrap(parse("https://ersinkoc.github.io/phonebox/pair/#\(query())"))
        XCTAssertEqual(link.pc, "My Mac")
        XCTAssertEqual(link.fingerprint, fp)
        XCTAssertEqual(link.port, 8766)
        XCTAssertEqual(link.hosts, ["192.168.1.24", "100.76.38.107"])
        XCTAssertEqual(link.code, code)
    }

    func testPhoneboxQueryLink() {
        XCTAssertNotNil(parse("phonebox://pair?\(query())"))
    }

    func testRejectsOtherHostsSchemesAndPaths() {
        XCTAssertNil(parse("https://evil.example/phonebox/pair/#\(query())"))
        XCTAssertNil(parse("https://ersinkoc.github.io/other/#\(query())"))
        XCTAssertNil(parse("http://ersinkoc.github.io/phonebox/pair/#\(query())"))
        XCTAssertNil(parse("phonebox://other?\(query())"))
        XCTAssertNil(parse("https://ersinkoc.github.io/phonebox/pair/?\(query())"), "data must be in the fragment")
    }

    func testUppercaseFingerprintIsNormalised() throws {
        let link = try XCTUnwrap(parse("phonebox://pair?\(query(fp: fp.uppercased()))"))
        XCTAssertEqual(link.fingerprint, fp)
    }

    func testRejectsBadFields() {
        XCTAssertNil(parse("phonebox://pair?\(query(v: "2"))"))
        XCTAssertNil(parse("phonebox://pair?\(query(fp: String(fp.dropLast())))"))
        XCTAssertNil(parse("phonebox://pair?\(query(fp: String(repeating: "zz", count: 32)))"))
        XCTAssertNil(parse("phonebox://pair?\(query(c: "short"))"))
        XCTAssertNil(parse("phonebox://pair?\(query(c: String(repeating: "a", count: 65)))"))
        XCTAssertNil(parse("phonebox://pair?\(query(c: "bad code with spaces!"))"))
        XCTAssertNil(parse("phonebox://pair?\(query(port: "0"))"))
        XCTAssertNil(parse("phonebox://pair?\(query(port: "70000"))"))
        XCTAssertNil(parse("phonebox://pair?\(query(port: "abc"))"))
    }

    func testPublicHostsAreFilteredAndAllPublicIsRejected() throws {
        let mixed = try XCTUnwrap(parse("phonebox://pair?\(query(h: "8.8.8.8,10.0.0.5"))"))
        XCTAssertEqual(mixed.hosts, ["10.0.0.5"])
        XCTAssertNil(parse("phonebox://pair?\(query(h: "8.8.8.8,example.com"))"))
        XCTAssertNil(parse("phonebox://pair?\(query(h: ""))"))
    }

    func testAtMostEightHosts() throws {
        let nine = (1...9).map { "10.0.0.\($0)" }.joined(separator: ",")
        XCTAssertEqual(try XCTUnwrap(parse("phonebox://pair?\(query(h: nine))")).hosts.count, 8)
    }

    func testComputerNameCleaning() throws {
        XCTAssertEqual(try XCTUnwrap(parse("phonebox://pair?\(query(pc: "A%00B%0AC%7F"))")).pc, "ABC")
        XCTAssertEqual(try XCTUnwrap(parse("phonebox://pair?\(query(pc: ""))")).pc, PairLink.defaultComputerName)
        XCTAssertEqual(try XCTUnwrap(parse("phonebox://pair?\(query(pc: "%20%20"))")).pc, PairLink.defaultComputerName)
        XCTAssertEqual(try XCTUnwrap(parse("phonebox://pair?\(query(pc: String(repeating: "x", count: 100)))")).pc.count, 64)
    }

    func testCheckCode() throws {
        let link = try XCTUnwrap(parse("phonebox://pair?\(query(fp: "0123abcd" + String(repeating: "0", count: 56)))"))
        XCTAssertEqual(link.check, "0123 ABCD")
    }

    func testIsLocalAddress() {
        for ok in ["10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.1.1", "100.64.0.1", "100.127.255.255", "100.76.38.107"] {
            XCTAssertTrue(PairLink.isLocalAddress(ok), ok)
        }
        for bad in ["172.15.0.1", "172.32.0.1", "192.169.1.1", "100.63.0.1", "100.128.0.1", "8.8.8.8", "10.0.0", "10.0.0.256",
                    "10.0.0.1.1", "10.0.0.x", "+10.0.0.1", "", "host.local", "10..0.1", "0010.0.0.1"] {
            XCTAssertFalse(PairLink.isLocalAddress(bad), bad)
        }
    }
}
