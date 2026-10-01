import Foundation

enum TextOps {
    static func apply(_ op: String, _ text: String, pattern: String, replacement: String,
                      limit: Int) -> String {
        switch op {
        case "count":
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            let chars = text.count
            let noSpace = text.filter { !$0.isWhitespace && !$0.isNewline }.count
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            return "行数 \(lines)｜字符 \(chars)｜去空白 \(noSpace)｜词 \(words)｜字节 \(text.utf8.count)"
        case "upper": return text.uppercased()
        case "lower": return text.lowercased()
        case "trim":
            return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: "\n")
        case "sort":
            return text.split(separator: "\n").sorted().joined(separator: "\n")
        case "dedup":
            var seen = Set<String>()
            var out: [String] = []
            for l in text.split(separator: "\n") where !seen.contains(String(l)) {
                seen.insert(String(l)); out.append(String(l))
            }
            return out.joined(separator: "\n")
        case "reverse":
            return String(text.reversed())
        case "replace":
            if pattern.isEmpty { return text }
            return text.replacingOccurrences(of: pattern, with: replacement)
        case "regex_replace":
            guard let re = try? NSRegularExpression(pattern: pattern) else {
                return "正则写错了：\(pattern)"
            }
            let ns = text as NSString
            return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length),
                                               withTemplate: replacement)
        case "extract":
            guard let re = try? NSRegularExpression(pattern: pattern) else {
                return "正则写错了：\(pattern)"
            }
            let ns = text as NSString
            var hits: [String] = []
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                for i in 1..<m.numberOfRanges where i < m.numberOfRanges {
                    let r = m.range(at: i)
                    if r.location != NSNotFound { hits.append(ns.substring(with: r)); break }
                }
                if m.numberOfRanges == 1 { hits.append(ns.substring(with: m.range)) }
                if hits.count >= limit { break }
            }
            return hits.isEmpty ? "没匹配到" : hits.joined(separator: "\n")
        case "split":
            let sep = pattern.isEmpty ? "\n" : pattern
            return text.components(separatedBy: sep).enumerated()
                .map { "\($0.offset): \($0.element)" }.joined(separator: "\n")
        case "lines":
            return text.split(separator: "\n").enumerated()
                .prefix(limit)
                .map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        case "slug":
            let s = text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: "-")
            return s.isEmpty ? text : s
        case "base64_encode":
            return Data(text.utf8).base64EncodedString()
        case "base64_decode":
            guard let d = Data(base64Encoded: text) else { return "不是合法 base64" }
            return String(decoding: d, as: UTF8.self)
        case "url_encode":
            return text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        case "url_decode":
            return text.removingPercentEncoding ?? text
        case "json_pretty":
            return JSONHelper.pretty(text)
        default:
            return "不支持的操作：\(op)。可用：count/upper/lower/trim/sort/dedup/reverse/replace/regex_replace/extract/split/lines/slug/base64_encode/base64_decode/url_encode/url_decode/json_pretty"
        }
    }

    static let ops = ["count", "upper", "lower", "trim", "sort", "dedup", "reverse", "replace",
                      "regex_replace", "extract", "split", "lines", "slug", "base64_encode",
                      "base64_decode", "url_encode", "url_decode", "json_pretty"]

    static func lineStats(old: String, new: String) -> (added: Int, removed: Int) {
        if old.isEmpty { return (new.isEmpty ? 0 : new.components(separatedBy: "\n").count, 0) }
        var bag: [String: Int] = [:]
        for l in old.components(separatedBy: "\n") { bag[l, default: 0] += 1 }
        var added = 0
        for l in new.components(separatedBy: "\n") {
            if (bag[l] ?? 0) > 0 { bag[l]! -= 1 } else { added += 1 }
        }
        var removed = 0
        for (_, n) in bag where n > 0 { removed += n }
        return (added, removed)
    }

    static func tableToCSV(_ text: String, sep: String) -> String {
        let rows = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var out: [String] = []
        for row in rows {
            var cells: [String]
            if row.contains("|") {
                cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first?.isEmpty == true { cells.removeFirst() }
                if cells.last?.isEmpty == true { cells.removeLast() }
                if cells.allSatisfy({ $0.allSatisfy { c in c == "-" || c == ":" || c == " " } }) { continue }
            } else if row.contains("\t") {
                cells = row.split(separator: "\t").map(String.init)
            } else {
                let s = sep.isEmpty ? "," : sep
                cells = row.components(separatedBy: s)
            }
            out.append(cells.map { csvCell($0) }.joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    private static func csvCell(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func diff(_ a: String, _ b: String) -> String {
        let al = a.components(separatedBy: "\n")
        let bl = b.components(separatedBy: "\n")
        let common = lcs(al, bl)
        var out: [String] = []
        var i = 0, j = 0, k = 0
        var hunk: [String] = []
        func flush() {
            if !hunk.isEmpty {
                out.append("@@ \(i + 1)/\(j + 1) @@")
                out.append(contentsOf: hunk)
                hunk = []
            }
        }
        while i < al.count && j < bl.count {
            if k < common.count && al[i] == common[k] && bl[j] == common[k] {
                if !hunk.isEmpty { hunk.append("  \(al[i])") }
                i += 1; j += 1; k += 1
            } else if k < common.count && al[i] == common[k] {
                hunk.append("- \(bl[j])")
                j += 1
            } else if k < common.count && bl[j] == common[k] {
                hunk.append("+ \(al[i])")
                i += 1
            } else {
                hunk.append("- \(bl[j])")
                hunk.append("+ \(al[i])")
                i += 1; j += 1
            }
        }
        while i < al.count { hunk.append("+ \(al[i])"); i += 1 }
        while j < bl.count { hunk.append("- \(bl[j])"); j += 1 }
        flush()
        if out.isEmpty { return "两段文本完全一致" }
        if out.count > 400 { return out.prefix(400).joined(separator: "\n") + "\n…(差异过多已截断)" }
        return out.joined(separator: "\n")
    }

    private static func lcs(_ a: [String], _ b: [String]) -> [String] {
        let n = min(a.count, 3000), m = min(b.count, 3000)
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] { dp[i][j] = dp[i - 1][j - 1] + 1 }
                else { dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]) }
            }
        }
        var out: [String] = []
        var i = n, j = m
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] { out.append(a[i - 1]); i -= 1; j -= 1 }
            else if dp[i - 1][j] >= dp[i][j - 1] { i -= 1 }
            else { j -= 1 }
        }
        return out.reversed()
    }
}

enum UnitConverter {
    static let tables: [String: [String: Double]] = [
        "length": ["mm": 0.001, "cm": 0.01, "m": 1, "km": 1000, "in": 0.0254, "ft": 0.3048,
                   "yd": 0.9144, "mi": 1609.344, "nmi": 1852, "里": 500, "丈": 3.3333, "尺": 0.3333, "寸": 0.03333],
        "mass": ["mg": 0.000001, "g": 0.001, "kg": 1, "t": 1000, "oz": 0.0283495, "lb": 0.453592,
                 "斤": 0.5, "两": 0.05, "担": 50],
        "data": ["bit": 0.125, "B": 1, "KB": 1024, "MB": 1024 * 1024, "GB": 1024 &* 1024 &* 1024,
                 "TB": 1024 &* 1024 &* 1024 &* 1024, "KiB": 1024, "MiB": 1024 * 1024],
        "time": ["ms": 0.001, "s": 1, "min": 60, "h": 3600, "d": 86400, "week": 604800,
                 "年": 31557600],
        "area": ["m2": 1, "km2": 1_000_000, "cm2": 0.0001, "ha": 10_000, "亩": 666.667,
                 "acre": 4046.86, "ft2": 0.092903],
        "volume": ["ml": 0.001, "L": 1, "m3": 1000, "gal": 3.78541, "qt": 0.946353,
                   "pint": 0.473176, "加仑": 3.78541],
        "speed": ["m/s": 1, "km/h": 1 / 3.6, "mph": 0.44704, "节": 0.514444],
    ]

    static func convert(_ value: Double, _ from: String, _ to: String, _ group: String) -> String {
        guard let t = tables[group] else {
            return "不支持的单位组：\(group)。可用：" + tables.keys.sorted().joined(separator: "/")
        }
        guard let f = t[from] ?? t[from.lowercased()], let g = t[to] ?? t[to.lowercased()] else {
            return "单位不认识。\(group) 可用单位：" + t.keys.sorted().joined(separator: ",")
        }
        let out = value * f / g
        return "\(trim(out)) \(to) = \(trim(value)) \(from)"
    }

    static func trim(_ d: Double) -> String {
        if abs(d) < 1e-9 { return "0" }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(format: "%.6g", d)
    }
}

enum DateCalc {
    static func run(_ op: String, _ base: String, _ amount: Double, _ unit: String,
                    _ format: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = format.isEmpty ? "yyyy-MM-dd HH:mm:ss" : format
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()
        var start = now
        if !base.isEmpty, let d = parse(base, cal: cal) { start = d }
        let n = Int(amount.rounded())
        func out(_ d: Date) -> String {
            let rel = d.timeIntervalSince(now)
            let past = rel < 0
            let a = abs(rel)
            let desc = a < 3600 ? "\(Int(a / 60)) 分钟" :
                (a < 86400 ? String(format: "%.1f 小时", a / 3600) :
                    String(format: "%.1f 天", a / 86400))
            return "\(fmt.string(from: d))｜星期\(weekdayCN(d, cal))｜\(past ? "距现在 \(desc)前" : "\(desc)后")"
        }
        switch op {
        case "now":
            let ts = Int(now.timeIntervalSince1970)
            return "\(fmt.string(from: now))｜星期\(weekdayCN(now, cal))｜时间戳 \(ts)"
        case "add":
            guard let d = shift(start, n, unit, cal) else { return "单位不认识：\(unit)" }
            return out(d)
        case "sub":
            guard let d = shift(start, -n, unit, cal) else { return "单位不认识：\(unit)" }
            return out(d)
        case "diff":
            guard let other = parse(amount.description, cal: cal) ?? parse(base, cal: cal),
                  let a = parse(format.isEmpty ? "" : base, cal: cal) else {
                return "diff 需要两个日期，base 填第一个，amount 不好用；改用两个日期字符串：" + base
            }
            let secs = abs(other.timeIntervalSince(a))
            return "相差 \(String(format: "%.2f 天", secs / 86400))（\(Int(secs / 60)) 分钟）"
        case "tz":
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = TimeZone(identifier: "UTC") ?? .current
            var local = fmt
            local.timeZone = cal.timeZone
            let utcStr = f.string(from: start)
            let lstr = local.string(from: start)
            let beijing = {
                var x = local
                x.timeZone = TimeZone(identifier: "Asia/Shanghai")
                return x.string(from: start)
            }()
            let ny = {
                var x = local
                x.timeZone = TimeZone(identifier: "America/New_York")
                return x.string(from: start)
            }()
            return "UTC \(utcStr)\n本地 \(lstr)\n北京 \(beijing)\n纽约 \(ny)"
        default:
            return "不支持的运算：\(op)。可用 now/add/sub/diff/tz"
        }
    }

    private static func parse(_ s: String, cal: Calendar) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let d = Double(t), abs(d) > 1_000_000 {
            return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d)
        }
        let patterns = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd",
                        "yyyy年MM月dd日", "MM-dd", "HH:mm:ss", "HH:mm"]
        for p in patterns {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = cal.timeZone
            f.dateFormat = p
            if let d = f.date(from: t) { return d }
        }
        var c = cal
        let lower = t.lowercased()
        if lower.hasPrefix("now") { return .now }
        let sign: Double = lower.hasSuffix(" ago") ? -1 : 1
        let body = lower.replacingOccurrences(of: " ago", with: "")
        if let n = Double(body.filter { "0123456789.".contains($0) }) {
            if body.contains("hour") || body.contains("h") { return cal.date(byAdding: .hour, value: Int(n * sign), from: .now) }
            if body.contains("day") || body.contains("d") { return cal.date(byAdding: .day, value: Int(n * sign), from: .now) }
            if body.contains("min") || body.contains("m") { return cal.date(byAdding: .minute, value: Int(n * sign), from: .now) }
        }
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.date(from: t)
    }

    private static func shift(_ d: Date, _ n: Int, _ unit: String, _ cal: Calendar) -> Date? {
        let u: Calendar.Component
        switch unit.lowercased() {
        case "day", "天", "日": u = .day
        case "week", "周", "星期": u = .weekOfYear
        case "month", "月": u = .month
        case "year", "年": u = .year
        case "hour", "小时", "时": u = .hour
        case "minute", "分钟", "分": u = .minute
        case "second", "秒", "s": u = .second
        default: return nil
        }
        return cal.date(byAdding: u, value: n, from: d)
    }

    private static func weekdayCN(_ d: Date, _ cal: Calendar) -> String {
        let w = cal.component(.weekday, from: d)
        return ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, w - 1))]
    }
}
