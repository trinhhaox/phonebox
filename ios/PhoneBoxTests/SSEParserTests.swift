import XCTest
@testable import PhoneBox

@MainActor
final class SSEParserTests: XCTestCase {
    private func parse(_ lines: [String]) -> [SSEEvent] {
        var p = SSEParser()
        return lines.compactMap { p.feed(line: $0) }
    }

    func testTwoEventsAndDefaultName() {
        let events = parse(["event: state", "data: {\"a\":1}", "", "data: hi", ""])
        XCTAssertEqual(events, [SSEEvent(event: "state", data: "{\"a\":1}"), SSEEvent(event: "message", data: "hi")])
    }

    func testMultipleDataLinesJoinWithoutSeparator() {
        XCTAssertEqual(parse(["data: ab", "data: cd", ""]).first?.data, "abcd")
    }

    func testCommentsAndBlankWithoutDataAreIgnored() {
        XCTAssertEqual(parse([": keepalive", "", "event: x", ""]), [])
    }

    func testLineSplitterHandlesCRLFPartialAndEmptyLines() {
        var s = LineSplitter()
        var out = [String]()
        for b in Array("data: 1\r\n\r\nda".utf8) { if let l = s.push(b) { out.append(l) } }
        XCTAssertEqual(out, ["data: 1", ""])
        for b in Array("ta: 2\n".utf8) { if let l = s.push(b) { out.append(l) } }
        XCTAssertEqual(out.last, "data: 2")
    }

    func testJSQuoteEscapesScriptBreakers() {
        let call = JSQuote.streamCall(event: "state", data: "\"</script>\u{2028}'\\")
        XCTAssertTrue(call.hasPrefix("window.onAgentStream && window.onAgentStream(\"state\", "))
        XCTAssertFalse(call.contains("\u{2028}"))
        XCTAssertTrue(call.contains("\\\\"))
    }

    func testAgentStreamDeliversOpenEventsAndClose() async {
        struct Fake: StreamSource {
            func openStream() async throws -> AsyncThrowingStream<String, Error> {
                AsyncThrowingStream { c in
                    ["event: state", "data: {}", ""].forEach { c.yield($0) }
                    c.finish()
                }
            }
        }
        var got = [String]()
        let done = expectation(description: "open+state+close")
        let stream = AgentStream(source: Fake(), reconnectDelay: { _ in .seconds(30) }) { event, data in
            got.append("\(event)|\(data)")
            if event == "close" { done.fulfill() }
        }
        stream.start()
        await fulfillment(of: [done], timeout: 5)
        stream.stop()
        XCTAssertEqual(got, [#"open|{"route":"wifi"}"#, "state|{}", "close|{}"])
    }
}
