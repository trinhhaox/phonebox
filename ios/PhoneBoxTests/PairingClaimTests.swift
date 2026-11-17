import XCTest
@testable import PhoneBox

final class ClaimStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    nonisolated(unsafe) static var handler: Handler = { _ in (200, Data()) }
    nonisolated(unsafe) static var seen = [(url: String, body: Data, headers: [String: String])]()
    private static let lock = NSLock()

    static func reset(_ h: @escaping Handler) { lock.lock(); handler = h; seen = []; lock.unlock() }
    static func urls() -> [String] { lock.lock(); defer { lock.unlock() }; return seen.map(\.url) }
    static func first() -> (url: String, body: Data, headers: [String: String])? { lock.lock(); defer { lock.unlock() }; return seen.first }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 2048)
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n > 0 { body = Data(buffer[0..<n]) }
            stream.close()
        }
        Self.lock.lock()
        Self.seen.append((request.url?.absoluteString ?? "", body, request.allHTTPHeaderFields ?? [:]))
        let h = Self.handler
        Self.lock.unlock()
        do {
            let (code, data) = try h(request)
            let r = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class PairingClaimTests: XCTestCase {
    private let fp = String(repeating: "ab", count: 32)
    private lazy var link = PairLink(pc: "My Mac", fingerprint: fp, port: 8766, hosts: ["192.168.1.24", "192.168.64.1"], code: "AbCdEfGhIjKlMnOp")

    private func claimer() -> PairingClaim {
        PairingClaim(model: "Apple iPhone15,2") {
            let c = URLSessionConfiguration.ephemeral
            c.protocolClasses = [ClaimStub.self]
            return c
        }
    }

    private func reply(fingerprint: String? = nil, token: String = "secret", port: Int? = 9000, hosts: [String]? = ["192.168.1.24", "8.8.8.8", "100.76.38.107"]) -> Data {
        var json: [String: Any] = ["enabled": true, "pc": "ignored", "token": token, "fingerprint": fingerprint ?? fp]
        if let port { json["port"] = port }
        if let hosts { json["hosts"] = hosts }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testSuccessBuildsComputerAndSendsExpectedRequest() async throws {
        ClaimStub.reset { _ in (200, self.reply(fingerprint: self.fp.uppercased())) }
        let pc = try await claimer().claim(link).get()
        XCTAssertEqual(pc, PairedComputer(id: fp, name: "My Mac", hosts: ["192.168.1.24", "100.76.38.107"], port: 9000, token: "secret"))
        let sent = try XCTUnwrap(ClaimStub.first())
        XCTAssertEqual(sent.url, "https://192.168.1.24:8766/api/pair/claim")
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")
        XCTAssertEqual(sent.headers["X-PhoneBox-Model"], "Apple iPhone15,2")
        XCTAssertEqual(String(data: sent.body, encoding: .utf8), #"{"code":"AbCdEfGhIjKlMnOp"}"#)
        XCTAssertNil(sent.headers["Authorization"])
    }

    func testFallsBackToLinkHostsAndPortWhenReplyHasNoUsableOnes() async throws {
        ClaimStub.reset { _ in (200, self.reply(port: nil, hosts: ["8.8.8.8"])) }
        let pc = try await claimer().claim(link).get()
        XCTAssertEqual(pc.hosts, link.hosts)
        XCTAssertEqual(pc.port, 8766)
    }

    func testFingerprintMismatchAborts() async {
        ClaimStub.reset { _ in (200, self.reply(fingerprint: String(repeating: "cd", count: 32))) }
        let result = await claimer().claim(link)
        XCTAssertEqual(result, .failure(.mismatchedReply(pc: "My Mac")))
        XCTAssertEqual(ClaimStub.urls().count, 1)
    }

    func test403StopsWithoutTryingOtherHosts() async {
        ClaimStub.reset { _ in (403, Data()) }
        let result = await claimer().claim(link)
        XCTAssertEqual(result, .failure(.codeRejected(pc: "My Mac")))
        XCTAssertEqual(ClaimStub.urls().count, 1)
    }

    func testUnreachableTriesNextHost() async throws {
        ClaimStub.reset { r in
            if r.url?.host == "192.168.1.24" { throw URLError(.cannotConnectToHost) }
            return (200, self.reply())
        }
        _ = try await claimer().claim(link).get()
        XCTAssertEqual(ClaimStub.urls().map { URL(string: $0)?.host }, ["192.168.1.24", "192.168.64.1"])
    }

    func testServerErrorThenAllFailedReportsUnreachableWithStatus() async {
        ClaimStub.reset { _ in (500, Data()) }
        let result = await claimer().claim(link)
        XCTAssertEqual(result, .failure(.unreachable(pc: "My Mac", hosts: link.hosts, status: 500)))
        XCTAssertEqual(ClaimStub.urls().count, 2)
    }

    func testBadBodyOrEmptyTokenCountsAsUnreachable() async {
        ClaimStub.reset { _ in (200, Data("not json".utf8)) }
        let first = await claimer().claim(link)
        ClaimStub.reset { _ in (200, self.reply(token: "")) }
        let second = await claimer().claim(link)
        let expected: Result<PairedComputer, PairingError> = .failure(.unreachable(pc: "My Mac", hosts: link.hosts, status: nil))
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
    }

    func testCertificateRejectionIsReportedAsDifferentCertificate() async {
        ClaimStub.reset { _ in throw URLError(.serverCertificateUntrusted) }
        let result = await claimer().claim(link)
        XCTAssertEqual(result, .failure(.differentCertificate(host: "192.168.64.1")))
    }

    func testErrorMessagesAreNonEmptyAndNeverContainSecrets() {
        let errors: [PairingError] = [.codeRejected(pc: "A"), .differentCertificate(host: "h"), .mismatchedReply(pc: "A"),
                                      .unreachable(pc: "A", hosts: ["h"], status: 500)]
        for e in errors { XCTAssertFalse(e.message.isEmpty) }
    }
}
