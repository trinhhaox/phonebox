import Foundation

struct SSEEvent: Equatable, Sendable {
    let event: String
    let data: String
}

/// Server-sent events as the agent emits them. Same rules as the Android client: `data:` lines of one event are joined
/// without a separator, `event:` defaults to "message", an event is delivered at the blank line only if it had data.
struct SSEParser {
    private var event = "message"
    private var data = ""

    mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = "message"; data = "" }
            return data.isEmpty ? nil : SSEEvent(event: event, data: data)
        }
        if line.hasPrefix("event:") {
            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            data += line.dropFirst(5).drop(while: { $0 == " " || $0 == "\t" })
        }
        return nil // comments (":") and other fields are ignored
    }
}

/// Splits a byte stream into lines on LF, dropping a trailing CR. Unlike `AsyncBytes.lines` it keeps empty lines,
/// which are what end an SSE event.
struct LineSplitter {
    private var buffer = [UInt8]()

    mutating func push(_ byte: UInt8) -> String? {
        guard byte == 0x0A else { buffer.append(byte); return nil }
        if buffer.last == 0x0D { buffer.removeLast() }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}
