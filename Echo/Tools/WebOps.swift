import Foundation

enum WebOps {
    struct Fetched {
        let title: String
        let text: String
    }

    static func fetch(_ raw: String, maxChars: Int) async throws -> Fetched {
        guard var comp = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)) else {
            throw ToolFailure("网址格式不对：\(raw)")
        }
        if comp.scheme == nil { comp.scheme = "https" }
        guard let url = comp.url else { throw ToolFailure("网址解析失败：\(raw)") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                     + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                     forHTTPHeaderField: "Accept")
        let (data, _) = try await ChatService.session.data(for: req)
        let html = decode(data)
        let title = firstMatch(html, pattern: "(?is)<title[^>]*>(.*?)</title>")?
            .stripHTML().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var body = html
        body = body.replacingOccurrences(of: "(?is)<script.*?</script>", with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: "(?is)<style.*?</style>", with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: "(?is)<noscript.*?</noscript>", with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: "(?is)<!--.*?-->", with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: "(?is)<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>", with: "\n", options: .regularExpression)
        let text = body.stripHTML().normalizedWhitespace()
        let cap = max(500, min(maxChars, 60_000))
        if text.count > cap {
            return Fetched(title: title, text: String(text.prefix(cap)) + "\n…(网页太长，已截断 \(text.count - cap) 字)")
        }
        return Fetched(title: title, text: text.isEmpty ? "(这个页面没抓到正文)" : text)
    }

    static func customSearch(endpoint: String, key: String, query: String) async throws -> String {
        guard var comp = URLComponents(string: endpoint) else { throw ToolFailure("搜索接口地址不对") }
        var items = comp.queryItems ?? []
        items.append(URLQueryItem(name: "q", value: query))
        items.append(URLQueryItem(name: "num", value: "10"))
        if !key.isEmpty { items.append(URLQueryItem(name: "key", value: key)) }
        comp.queryItems = items
        guard let url = comp.url else { throw ToolFailure("搜索接口地址拼不出来") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await ChatService.session.data(for: req)
        let s = String(decoding: data, as: UTF8.self)
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let arr = (obj as? [String: Any])?["results"] as? [[String: Any]] {
                return arr.prefix(10).enumerated().map { i, r in
                    let t = r["title"] as? String ?? r["name"] as? String ?? ""
                    let u = r["url"] as? String ?? r["link"] as? String ?? ""
                    let s = r["content"] as? String ?? r["snippet"] as? String ?? ""
                    return "\(i + 1). \(t)\n   \(u)\n   \(s.prefix(200))"
                }.joined(separator: "\n\n")
            }
            return String(s.prefix(4000))
        }
        return String(s.prefix(4000))
    }

    static func search(_ query: String, count: Int) async throws -> String {
        let engines = [
            ("https://html.duckduckgo.com/html/", "q"),
            ("https://lite.duckduckgo.com/lite/", "q"),
            ("https://www.bing.com/search", "q"),
        ]
        for (base, param) in engines {
            guard var comp = URLComponents(string: base) else { continue }
            comp.queryItems = [URLQueryItem(name: param, value: query)]
            guard let url = comp.url else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                         + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await ChatService.session.data(for: req) else { continue }
            let html = decode(data)
            let hits = parseHits(html, limit: max(1, min(count, 10)))
            if !hits.isEmpty { return hits }
        }
        throw ToolFailure("搜索没返回结果（这类接口容易被反爬）。改用 web_fetch 直接抓你已知的网址。")
    }

    private static func parseHits(_ html: String, limit: Int) -> String {
        var out: [String] = []
        let linkPat = "(?is)<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>"
        guard let re = try? NSRegularExpression(pattern: linkPat) else { return "" }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if out.count >= limit { break }
            let href = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2))
            let title = inner.stripHTML().trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count > 4, href.hasPrefix("http") else { continue }
            if href.contains("duckduckgo.com/") || href.contains("bing.com/") { continue }
            let url = href.contains("uddg=") ? (URLComponents(string: href)?.queryItems?
                .first { $0.name == "uddg" }?.value ?? href) : href
            out.append("• \(title)\n  \(url)")
        }
        return out.joined(separator: "\n\n")
    }

    private static func firstMatch(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if m.numberOfRanges > 1 { return ns.substring(with: m.range(at: 1)) }
        return ns.substring(with: m.range)
    }

    private static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        let encodings = [String.Encoding.isoLatin1, .windowsCP1252, .shiftJIS]
        for e in encodings {
            if let s = String(data: data, encoding: e) { return s }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct ToolFailure: Error, CustomStringConvertible {
    let message: String
    init(_ m: String) { message = m }
    var description: String { message }
}

extension String {
    func stripHTML() -> String {
        var s = self
        s = s.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                                          "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—",
                                          "&ndash;": "–", "&hellip;": "…", "&copy;": "©", "&reg;": "®",
                                          "&times;": "×", "&divide;": "÷", "&rarr;": "→", "&larr;": "←",
                                          "&middot;": "·", "&lsquo;": "‘", "&rsquo;": "’", "&ldquo;": "“",
                                          "&rdquo;": "”", "&bull;": "·", "&ensp;": " ", "&emsp;": " "]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        if let r = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = s as NSString
            var out = s
            for m in r.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let code = Int(ns.substring(with: m.range(at: 1))), let uni = Unicode.Scalar(code) {
                    out.replaceSubrange(Range(m.range, in: out)!, with: String(Character(uni)))
                }
            }
            s = out
        }
        if let r = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let ns = s as NSString
            var out = s
            for m in r.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let code = Int(ns.substring(with: m.range(at: 1)), radix: 16), let uni = Unicode.Scalar(code) {
                    out.replaceSubrange(Range(m.range, in: out)!, with: String(Character(uni)))
                }
            }
            s = out
        }
        return s
    }

    func normalizedWhitespace() -> String {
        var s = self
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[ \n]+|[ \n]+$", with: "", options: .regularExpression)
        return s
    }

    func clamped(_ n: Int) -> String {
        count <= n ? self : String(prefix(n)) + "…(\(count - n) 字未显示)"
    }
}
