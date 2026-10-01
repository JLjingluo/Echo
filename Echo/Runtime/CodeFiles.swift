import Foundation

struct ExtractedCode: Identifiable, Hashable {
    let name: String
    let ext: String
    let content: String
    var id: String { name }
    var lineCount: Int { content.components(separatedBy: "\n").count }
}

enum CodeFiles {
    static let extMap: [String: String] = [
        "html": "html", "htm": "html", "xml": "xml", "svg": "svg",
        "js": "js", "javascript": "js", "jsx": "jsx", "mjs": "mjs", "node": "js",
        "ts": "ts", "tsx": "tsx", "typescript": "ts",
        "css": "css", "scss": "scss", "less": "less",
        "json": "json", "md": "md", "markdown": "md", "csv": "csv", "tsv": "tsv",
        "txt": "txt", "py": "py", "python": "py", "sh": "sh", "bash": "sh",
        "zsh": "sh", "yaml": "yaml", "yml": "yml", "sql": "sql", "swift": "swift",
        "rs": "rs", "rust": "rs", "go": "go", "java": "java", "kt": "kt",
        "c": "c", "h": "h", "cpp": "cpp", "ini": "ini", "toml": "toml",
    ]

    static let defaultNames: [String: String] = [
        "html": "index.html", "js": "main.js", "ts": "main.ts", "css": "style.css",
        "json": "data.json", "md": "notes.md", "svg": "image.svg", "py": "script.py",
        "sh": "run.sh", "csv": "table.csv", "txt": "notes.txt", "xml": "data.xml",
    ]

    private static let proseName: NSRegularExpression? = try? NSRegularExpression(
        pattern: "([A-Za-z0-9_\\-.]{1,48})\\.(html?|js|jsx|ts|tsx|css|json|md|svg|csv|py|sh|txt|yml|yaml|xml)")

    static func candidates(from text: String, hint: String, skip: Set<String>) -> [ExtractedCode] {
        var out: [ExtractedCode] = []
        var used = Set(skip.map { $0.lowercased() })
        var prose = ""
        for seg in CodeSplitter.segments(text) {
            if seg.kind != .code { prose = seg.body; continue }
            let info = seg.lang.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = info.split(whereSeparator: { " :|,\t()[]{}".contains($0) }).map(String.init)
            let lang = (tokens.first ?? "").lowercased()
            guard let ext = extMap[lang] else { continue }
            guard looksComplete(ext: ext, body: seg.body) else { continue }
            var name = tokens.first(where: { $0.lowercased().hasSuffix("." + ext) }) ?? ""
            if name.isEmpty, let n = nameFromProse(prose, ext: ext) { name = n }
            if name.isEmpty { name = defaultNames[ext] ?? "echo.\(ext)" }
            name = normalize(name, ext: ext)
            if used.contains(name.lowercased()) { name = normalize(slug(hint), ext: ext) }
            if used.contains(name.lowercased()) { continue }
            used.insert(name.lowercased())
            out.append(ExtractedCode(name: name, ext: ext, content: seg.body))
            if out.count >= 6 { break }
        }
        return out
    }

    static func looksComplete(ext: String, body: String) -> Bool {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard b.count >= 140 else { return false }
        let lines = b.components(separatedBy: "\n").count
        let low = b.lowercased()
        switch ext {
        case "html", "htm", "xml":
            return low.contains("</html>") || low.contains("<!doctype html") || low.contains("</svg>")
                || low.contains("</rss>") || low.contains("</svg")
        case "svg":
            return low.contains("</svg>")
        case "css", "scss", "less":
            return lines >= 6 && b.contains("}")
        case "js", "jsx", "ts", "tsx", "mjs":
            return lines >= 10 || b.contains("function") || b.contains("=>")
                || b.contains("import ") || b.contains("export ") || b.contains("document.")
        case "json":
            return (try? JSONSerialization.jsonObject(with: Data(b.utf8))) != nil
        case "md", "txt":
            return lines >= 8
        case "csv", "tsv":
            return lines >= 3
        case "py", "sh":
            return lines >= 8
        default:
            return lines >= 10
        }
    }

    static func normalize(_ raw: String, ext: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        n = n.replacingOccurrences(of: "/", with: "-")
        n = n.replacingOccurrences(of: "\\", with: "-")
        n = n.replacingOccurrences(of: " ", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        if !n.lowercased().hasSuffix("." + ext) {
            let base = (n as NSString).deletingPathExtension
            n = (base.isEmpty ? "echo" : base) + "." + ext
        }
        if n.count > 64 { n = String(n.prefix(48)) + "." + ext }
        return n
    }

    static func slug(_ hint: String) -> String {
        var keep = ""
        for c in hint {
            if c.isLetter || c.isNumber {
                keep.append(c)
            } else if keep.last != "-" {
                keep.append("-")
            }
            if keep.count >= 16 { break }
        }
        let s = keep.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "echo" : s
    }

    private static func nameFromProse(_ prose: String, ext: String) -> String? {
        guard let re = proseName else { return nil }
        let ns = prose as NSString
        let hits = re.matches(in: prose, range: NSRange(location: 0, length: ns.length))
        guard let last = hits.last, last.numberOfRanges >= 3 else { return nil }
        let base = ns.substring(with: last.range(at: 1))
        let found = ns.substring(with: last.range(at: 2)).lowercased()
        let mapped = extMap[found] ?? found
        guard mapped == ext else { return nil }
        return base + "." + found
    }
}
