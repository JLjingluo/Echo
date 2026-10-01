import Foundation

struct SSEEvent: Equatable {
    let type: String
    let data: String
}

enum SSEParser {
    static func parse(_ chunk: String, buffer: inout String) -> [SSEEvent] {
        buffer += chunk
        var events: [SSEEvent] = []
        while let r = buffer.firstRange(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<r.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<r.upperBound)
            if let e = decode(block) { events.append(e) }
        }
        while buffer.hasPrefix("\n") { buffer.removeFirst() }
        return events
    }

    private static func decode(_ block: String) -> SSEEvent? {
        var type = "message"
        var dataLines: [String] = []
        for raw in block.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.hasPrefix("event:") {
                type = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        guard !dataLines.isEmpty else { return nil }
        let joined = dataLines.joined(separator: "\n")
        if joined == "[DONE]" { return SSEEvent(type: "done", data: "[DONE]") }
        if let d = joined.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: d)) == nil {
            return nil
        }
        return SSEEvent(type: type, data: joined)
    }
}
