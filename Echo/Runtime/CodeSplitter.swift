import Foundation

enum CodeSplitter {
    struct Seg {
        let kind: BlkKind
        let lang: String
        let body: String
    }

    static func segments(_ text: String) -> [Seg] {
        var out: [Seg] = []
        var prose: [String] = []
        var body: [String] = []
        var lang = ""
        var marker = "```"
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !inFence, t.hasPrefix("```") || t.hasPrefix("~~~") {
                flush(&out, prose: &prose)
                inFence = true
                marker = String(t.prefix(3))
                lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                body = []
                continue
            }
            if inFence, t.hasPrefix(marker), t.dropFirst(3).allSatisfy({ $0 == "`" || $0 == "~" }) {
                out.append(Seg(kind: .code, lang: lang, body: body.joined(separator: "\n")))
                inFence = false
                lang = ""
                body = []
                continue
            }
            if inFence { body.append(line) } else { prose.append(line) }
        }
        if inFence { out.append(Seg(kind: .code, lang: lang, body: body.joined(separator: "\n"))) }
        flush(&out, prose: &prose)
        return out.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func flush(_ out: inout [Seg], prose: inout [String]) {
        let s = prose.joined(separator: "\n")
        if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(Seg(kind: .text, lang: "", body: s))
        }
        prose = []
    }
}
