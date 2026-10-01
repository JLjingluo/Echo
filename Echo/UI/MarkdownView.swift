import SwiftUI

enum MD {
    static func inline(_ s: String, size: CGFloat = 17) -> AttributedString {
        let chars = Array(s)
        var out = AttributedString()
        var i = 0

        func add(_ str: String, _ f: Font, _ c: Color? = nil, _ link: URL? = nil,
                 _ bg: Color? = nil) {
            guard !str.isEmpty else { return }
            var a = AttributeContainer()
            a.font = f
            if let c { a.foregroundColor = c }
            if let l = link { a.link = l }
            if let bg { a.backgroundColor = bg }
            out.append(AttributedString(str, attributes: a))
        }

        func find(_ seq: [Character], from start: Int) -> Int? {
            var j = start
            while j + seq.count <= chars.count {
                if Array(chars[j..<(j + seq.count)]) == seq { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            if c == "`", let e = find(["`"], from: i + 1) {
                add(String(chars[(i + 1)..<e]), .system(size: size * 0.85, design: .monospaced),
                    Ench.text, nil, Ench.secondaryBackground)
                i = e + 1
                continue
            }
            if (c == "*" || c == "_"), let e = find([c, c], from: i + 1), e > i + 1 {
                add(String(chars[(i + 2)..<e]), .system(size: size, weight: .semibold))
                i = e + 2
                continue
            }
            if c == "*", let e = find(["*"], from: i + 1), e > i + 1 {
                add(String(chars[(i + 1)..<e]), .system(size: size).italic())
                i = e + 1
                continue
            }
            if c == "[", let close = find(["]"], from: i + 1), close + 1 < chars.count,
               chars[close + 1] == "(", let e = find([")"], from: close + 2) {
                let label = String(chars[(i + 1)..<close])
                let url = String(chars[(close + 2)..<e])
                add(label, .system(size: size), Ench.link, URL(string: url))
                i = e + 1
                continue
            }
            var j = i + 1
            while j < chars.count, !"`*[_".contains(chars[j]) { j += 1 }
            add(String(chars[i..<j]), .system(size: size))
            i = j
        }
        return out
    }
}

struct MDBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case para
        case quote
        case bullet
        case ordered(Int)
        case rule
        case table
    }
    let id = UUID()
    let kind: Kind
    let lines: [String]
}

enum MDParse {
    static func blocks(_ text: String) -> [MDBlock] {
        var out: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var para: [String] = []
        var numbered = 0

        func flushPara() {
            let joined = para.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { out.append(MDBlock(kind: .para, lines: [joined])) }
            para = []
        }

        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                flushPara()
                numbered = 0
                i += 1
                continue
            }
            if t.hasPrefix("#"), t.dropFirst().first.map { $0 == " " || $0 == "#" } ?? true {
                flushPara()
                let level = t.prefix(while: { $0 == "#" }).count
                out.append(MDBlock(kind: .heading(min(max(level, 1), 4)),
                                   lines: [String(t.dropFirst(level)).trimmingCharacters(in: .whitespaces)]))
                i += 1
                continue
            }
            if t.count < 8, t.allSatisfy({ "-* _".contains($0) }), t.contains("-") || t.contains("*") {
                flushPara()
                out.append(MDBlock(kind: .rule, lines: []))
                i += 1
                continue
            }
            if t.hasPrefix(">") {
                flushPara()
                var buf: [String] = []
                while i < lines.count {
                    let x = lines[i].trimmingCharacters(in: .whitespaces)
                    if !x.hasPrefix(">") { break }
                    buf.append(String(x.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(MDBlock(kind: .quote, lines: buf))
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                flushPara()
                numbered = 0
                out.append(MDBlock(kind: .bullet,
                                   lines: [String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)]))
                i += 1
                continue
            }
            if let num = orderedPrefix(t) {
                flushPara()
                numbered += 1
                out.append(MDBlock(kind: .ordered(numbered), lines: [num]))
                i += 1
                continue
            }
            if t.hasPrefix("|"), t.filter({ $0 == "|" }).count >= 2 {
                flushPara()
                var buf: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    buf.append(lines[i].trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(MDBlock(kind: .table, lines: buf))
                continue
            }
            para.append(t)
            i += 1
        }
        flushPara()
        return out
    }

    private static func orderedPrefix(_ t: String) -> String? {
        guard let dot = t.firstIndex(of: "."), dot != t.startIndex else { return nil }
        let head = t[t.startIndex..<dot]
        guard head.count <= 3, head.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = t[t.index(after: dot)...]
        guard rest.first == " " else { return nil }
        return String(rest).trimmingCharacters(in: .whitespaces)
    }
}

struct MarkdownView: View {
    let text: String
    var size: CGFloat = Ench.body

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.8) {
            ForEach(MDParse.blocks(text)) { block in
                row(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Ench.text)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ b: MDBlock) -> some View {
        switch b.kind {
        case .heading(let level):
            let s = size * (level <= 1 ? 2 : level == 2 ? 1.5 : 1.25)
            VStack(alignment: .leading, spacing: 0) {
                Text(MD.inline(b.lines.joined(separator: " "), size: s))
                    .font(.system(size: s, weight: .semibold))
                    .lineSpacing(s * 0.125)
                    .padding(.bottom, s * 0.3)
                if level <= 2 {
                    Divider().overlay(Ench.divider)
                }
            }
            .padding(.top, level <= 1 ? 24 : 16)
            .padding(.bottom, level <= 1 ? 8 : 4)
            .fixedSize(horizontal: false, vertical: true)
        case .para:
            Text(MD.inline(b.lines.joined(separator: "\n"), size: size))
                .lineSpacing(size * 0.25)
                .fixedSize(horizontal: false, vertical: true)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Ench.border).frame(width: 3)
                    .padding(.vertical, 2)
                Text(MD.inline(b.lines.joined(separator: "\n"), size: size))
                    .foregroundStyle(Ench.secondaryText)
                    .lineSpacing(size * 0.25)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•").font(.system(size: size)).foregroundStyle(Ench.secondaryText)
                Text(MD.inline(b.lines.joined(separator: " "), size: size))
                    .lineSpacing(size * 0.25)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .ordered(let n):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(n).")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Ench.secondaryText)
                    .frame(width: 20, alignment: .leading)
                Text(MD.inline(b.lines.joined(separator: " "), size: size))
                    .lineSpacing(size * 0.25)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider().overlay(Ench.divider).padding(.vertical, 6)
        case .table:
            MDTable(rows: b.lines, size: size)
        }
    }
}

struct MDTable: View {
    let rows: [String]
    let size: CGFloat

    var grid: [[String]] {
        rows.map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
            .filter { row in !row.allSatisfy { $0.replacingOccurrences(of: "[-: ]", with: "").isEmpty } }
            .map { row in
                var r = row
                if r.first?.isEmpty == true { r.removeFirst() }
                if r.last?.isEmpty == true { r.removeLast() }
                return r
            }
    }

    var body: some View {
        let g = grid
        return VStack(spacing: 0) {
            ForEach(Array(g.enumerated()), id: \.offset) { idx, line in
                HStack(spacing: 0) {
                    ForEach(Array(line.enumerated()), id: \.offset) { cIdx, cell in
                        Text(MD.inline(cell, size: size - 2))
                            .font(.system(size: size - 2, weight: idx == 0 ? .semibold : .regular))
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if cIdx < line.count - 1 { Divider() }
                    }
                }
                if idx < g.count - 1 { Divider() }
            }
        }
        .background(Color.codeBG)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.quaternary))
    }
}
