import Foundation

enum ToolSummary {
    static func detail(_ id: ToolID, _ args: String) -> String? {
        let a = Args(json: args)
        switch id {
        case .write_file:
            let n = a.s("name")
            let lines = a.s("content").components(separatedBy: "\n").count
            return n.isEmpty ? nil : "\(n) +\(lines)行"
        case .read_file, .ocr_image, .delete_file, .table_to_csv, .text_ops:
            let n = a.s("name").isEmpty ? a.s("text").clamped(40) : a.s("name")
            return n.isEmpty ? nil : n
        case .list_files:
            let s = a.s("subdir")
            return s.isEmpty ? "工作区" : s
        case .move_file:
            let f = a.s("from"), t = a.s("to")
            return f.isEmpty ? nil : "\(f) → \(t)"
        case .diff_text:
            let aName = a.s("a_name").isEmpty ? "a" : a.s("a_name")
            let bName = a.s("b_name").isEmpty ? "b" : a.s("b_name")
            return "\(aName) ↔ \(bName)"
        case .run_js:
            let first = a.s("code").components(separatedBy: "\n")
                .first?.trimmingCharacters(in: .whitespaces) ?? ""
            return first.isEmpty ? nil : first.clamped(48)
        case .web_fetch:
            return a.s("url").isEmpty ? nil : a.s("url")
        case .web_search:
            return a.s("query").isEmpty ? nil : a.s("query")
        case .date_calc:
            let op = a.s("op")
            return op.isEmpty ? nil : "\(op) \(a.s("base"))".clamped(48)
        case .unit_convert:
            let f = a.s("from"), t = a.s("to")
            return f.isEmpty ? nil : "\(f) → \(t)"
        case .make_qrcode:
            return a.s("save_as").isEmpty ? a.s("text").clamped(40) : a.s("save_as")
        case .ask_user:
            let q = a.s("question")
            return q.isEmpty ? nil : q.clamped(56)
        }
    }

    static func title(_ id: ToolID, args: String) -> String {
        guard let d = detail(id, args) else { return id.label }
        return "\(id.label) \(d)"
    }

    static func id(of name: String) -> ToolID? { ToolID(rawValue: name) }
}
