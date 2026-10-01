import Foundation

enum ToolOutcome {
    case text(String)
    case file(name: String, url: URL, bytes: Int, preview: String, added: Int, removed: Int)

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .file(let n, let u, let b, _, let a, let r):
            return "已写入 \(n)（\(Self.sizeText(b))，+\(a) −\(r) 行），路径 \(u.path)"
        }
    }

    var modelText: String {
        switch self {
        case .text(let s): return s
        case .file(let n, _, _, _, let a, let r): return "文件已写入 \(n)（+\(a) −\(r) 行），已保存到手机本地工作区。"
        }
    }

    static func sizeText(_ value: Int) -> String {
        if value < 1024 { return "\(value) B" }
        if value < 1024 * 1024 { return String(format: "%.1f KB", Double(value) / 1024) }
        return String(format: "%.1f MB", Double(value) / 1024 / 1024)
    }
}

struct Args {
    let dict: [String: Any]

    init(_ d: [String: Any]) { dict = d }
    init(json: String) { dict = JSONHelper.dict(json) }

    func s(_ key: String, _ fallback: String = "") -> String {
        if let v = dict[key] as? String { return v }
        if let v = dict[key] as? NSNumber { return v.stringValue }
        return fallback
    }

    func i(_ key: String, _ fallback: Int = 0) -> Int {
        if let v = dict[key] as? Int { return v }
        if let v = dict[key] as? NSNumber { return v.intValue }
        if let v = dict[key] as? String, let n = Int(v.trimmingCharacters(in: .whitespaces)) { return n }
        return fallback
    }

    func d(_ key: String, _ fallback: Double = 0) -> Double {
        if let v = dict[key] as? Double { return v }
        if let v = dict[key] as? NSNumber { return v.doubleValue }
        if let v = dict[key] as? String, let n = Double(v) { return n }
        return fallback
    }

    func b(_ key: String, _ fallback: Bool = false) -> Bool {
        if let v = dict[key] as? Bool { return v }
        if let v = dict[key] as? NSNumber { return v.boolValue }
        if let v = dict[key] as? String { return ["true", "1", "yes", "y"].contains(v.lowercased()) }
        return fallback
    }
}

enum ToolKit {
    static func allowedTools(_ settings: AppSettings) -> [ToolID] {
        ToolID.allCases.filter { settings.toolAllowed($0) }
    }

    static func schemas(_ settings: AppSettings) -> [ToolSchema] {
        allowedTools(settings).compactMap { schema(for: $0) }
    }

    static func schema(for id: ToolID) -> ToolSchema? {
        switch id {
        case .write_file:
            return ToolSchema(name: id.rawValue,
                description: "在工作区创建或覆盖一个文件。要产出任何文件都用它。",
                parameters: obj([
                    "name": str("文件名，带扩展名，例如 report.md、src/main.swift。可用 dir/ 建子目录"),
                    "content": str("文件的完整内容"),
                ], ["name", "content"]))
        case .read_file:
            return ToolSchema(name: id.rawValue,
                description: "读取工作区里某个文件的文本内容。",
                parameters: obj([
                    "name": str("相对路径文件名"),
                    "max_bytes": ["type": "integer", "description": "最多读多少字节，默认 40000"],
                ], ["name"]))
        case .list_files:
            return ToolSchema(name: id.rawValue,
                description: "列出工作区里的文件（名称、大小、修改时间）。",
                parameters: obj([
                    "subdir": str("子目录名，留空表示根目录"),
                    "recursive": ["type": "boolean", "description": "是否递归，默认 false"],
                ], []))
        case .delete_file:
            return ToolSchema(name: id.rawValue,
                description: "删除工作区里的一个文件或目录。",
                parameters: obj(["name": str("相对路径")], ["name"]))
        case .move_file:
            return ToolSchema(name: id.rawValue,
                description: "移动或重命名工作区里的文件。",
                parameters: obj([
                    "from": str("原路径"),
                    "to": str("新路径"),
                ], ["from", "to"]))
        case .text_ops:
            return ToolSchema(name: id.rawValue,
                description: "对文本做处理。op 可选：count/upper/lower/trim/sort/dedup/reverse/replace/regex_replace/extract/split/lines/slug/base64_encode/base64_decode/url_encode/url_decode/json_pretty",
                parameters: obj([
                    "op": ["type": "string", "enum": TextOps.ops],
                    "text": str("要处理的文本，和 name 二选一"),
                    "name": str("要处理的工作区文件名，和 text 二选一"),
                    "pattern": str("匹配模式或分隔符，按 op 需要填"),
                    "replacement": str("替换文本"),
                    "limit": ["type": "integer", "description": "最多输出多少条/行，默认 200"],
                ], ["op"]))
        case .diff_text:
            return ToolSchema(name: id.rawValue,
                description: "对比两段文本或两个文件的差异，输出 diff。",
                parameters: obj([
                    "a": str("文本 A"),
                    "b": str("文本 B"),
                    "a_name": str("文件 A 名，给了就优先于 a"),
                    "b_name": str("文件 B 名，给了就优先于 b"),
                ], []))
        case .run_js:
            return ToolSchema(name: id.rawValue,
                description: "在手机本地跑 JavaScript（JavaScriptCore）。用 emit(...) 或 console.log(...) 输出结果，input 变量可传入数据。适合精确计算、数据处理，比你自己算可靠。",
                parameters: obj([
                    "code": str("JS 代码"),
                    "input": str("可选：一个 JSON 值，代码里用变量 input 取"),
                ], ["code"]))
        case .web_fetch:
            return ToolSchema(name: id.rawValue,
                description: "抓取一个网页的正文文本。",
                parameters: obj([
                    "url": str("完整网址"),
                    "max_chars": ["type": "integer", "description": "最多返回多少字，默认 8000"],
                ], ["url"]))
        case .web_search:
            return ToolSchema(name: id.rawValue,
                description: "联网搜索关键词，返回标题和链接列表。",
                parameters: obj([
                    "query": str("搜索词"),
                    "count": ["type": "integer", "description": "返回几条，默认 8"],
                ], ["query"]))
        case .table_to_csv:
            return ToolSchema(name: id.rawValue,
                description: "把 Markdown 表格、TSV 或对齐文本转成 CSV。",
                parameters: obj([
                    "text": str("表格文本"),
                    "name": str("或指定工作区文件名"),
                    "sep": str("纯分隔符文本的分隔符，默认逗号"),
                ], []))
        case .date_calc:
            return ToolSchema(name: id.rawValue,
                description: "日期时间计算。op：now/add/sub/diff/tz。",
                parameters: obj([
                    "op": ["type": "string", "enum": ["now", "add", "sub", "diff", "tz"]],
                    "base": str("基准日期，如 2026-08-09 或 2026-08-09 14:30:00，留空用现在；diff 时填另一个日期"),
                    "amount": ["type": "number", "description": "数量"],
                    "unit": ["type": "string", "enum": ["day", "week", "month", "year", "hour", "minute", "second"]],
                    "format": str("输出格式，默认 yyyy-MM-dd HH:mm:ss"),
                ], ["op"]))
        case .unit_convert:
            return ToolSchema(name: id.rawValue,
                description: "单位换算。group 可选 length/mass/data/time/area/volume/speed。",
                parameters: obj([
                    "value": ["type": "number", "description": "数值"],
                    "from": str("原单位，如 m、km、MB、斤"),
                    "to": str("目标单位"),
                    "group": ["type": "string", "enum": Array(UnitConverter.tables.keys.sorted())],
                ], ["value", "from", "to", "group"]))
        case .make_qrcode:
            return ToolSchema(name: id.rawValue,
                description: "生成二维码 PNG 存到工作区。",
                parameters: obj([
                    "text": str("二维码内容"),
                    "save_as": str("保存的文件名，默认 qrcode.png"),
                    "size": ["type": "integer", "description": "边长像素，默认 512"],
                ], ["text"]))
        case .ocr_image:
            return ToolSchema(name: id.rawValue,
                description: "识别工作区里图片中的文字（OCR）。",
                parameters: obj(["name": str("图片文件名")], ["name"]))
        case .ask_user:
            return ToolSchema(name: id.rawValue,
                description: "当面问用户一个问题。只在缺的信息会导致结果完全不对时用（比如「发给谁」「哪个城市」「要不要带预算上限」），一次最多问一个。给 2 到 4 个候选项，用户点一下就答；用户也可以自己打字。能合理推断的别问。",
                parameters: obj([
                    "question": str("要问的一句话，不超过 40 字"),
                    "options": ["type": "array", "items": ["type": "string"],
                                "description": "2 到 4 个候选短答"],
                ], ["question"]))
        }
    }

    private static func obj(_ props: [String: Any], _ required: [String]) -> [String: Any] {
        var d: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { d["required"] = required }
        return d
    }

    private static func str(_ desc: String) -> [String: Any] {
        ["type": "string", "description": desc]
    }

    @MainActor
    static func execute(_ id: ToolID, json: String, settings: AppSettings) async -> ToolOutcome {
        let a = Args(json: json)
        do {
            switch id {
            case .write_file:
                let name = a.s("name")
                let content = a.s("content")
                guard !name.isEmpty else { return .text("失败：没给文件名") }
                let old = FileStore.shared.exists(name)
                    ? ((try? FileStore.shared.read(name, maxBytes: 400_000)) ?? "") : ""
                let url = try FileStore.shared.write(name, content)
                let stats = TextOps.lineStats(old: old, new: content)
                let preview = content.isEmpty ? "(空文件)" : String(content.prefix(600))
                return .file(name: url.lastPathComponent, url: url,
                             bytes: (try? Data(contentsOf: url).count) ?? content.utf8.count,
                             preview: preview, added: stats.added, removed: stats.removed)
            case .read_file:
                let text = try FileStore.shared.read(a.s("name"),
                                                    maxBytes: a.i("max_bytes", 40_000))
                return .text(text)
            case .list_files:
                if a.b("recursive") {
                    let urls = FileStore.shared.allURLs()
                    if urls.isEmpty { return .text("工作区是空的") }
                    return .text(urls.map { $0.path.replacingOccurrences(of: FileStore.shared.root.path + "/", with: "") }
                        .joined(separator: "\n"))
                }
                let items = FileStore.shared.list(a.s("subdir"))
                if items.isEmpty { return .text("没有文件") }
                let f = DateFormatter()
                f.dateFormat = "MM-dd HH:mm"
                return .text(items.map {
                    "\($0.isDir ? "[目录]" : "[文件]") \($0.name)  \($0.sizeText)  \(f.string(from: $0.modified))"
                }.joined(separator: "\n"))
            case .delete_file:
                _ = try FileStore.shared.delete(a.s("name"))
                return .text("已删除 \(a.s("name"))")
            case .move_file:
                let dst = try FileStore.shared.move(from: a.s("from"), to: a.s("to"))
                return .text("已移动到 \(dst.path)")
            case .text_ops:
                var text = a.s("text")
                if text.isEmpty, !a.s("name").isEmpty { text = try FileStore.shared.read(a.s("name")) }
                let out = TextOps.apply(a.s("op"), text, pattern: a.s("pattern"),
                                        replacement: a.s("replacement"), limit: a.i("limit", 200))
                return .text(out.isEmpty ? "(结果为空)" : out)
            case .diff_text:
                let aText = a.s("a_name").isEmpty ? a.s("a") : (try? FileStore.shared.read(a.s("a_name"))) ?? ""
                let bText = a.s("b_name").isEmpty ? a.s("b") : (try? FileStore.shared.read(a.s("b_name"))) ?? ""
                if aText.isEmpty && bText.isEmpty { return .text("两段都是空的，先给 a/b 或 a_name/b_name") }
                return .text(TextOps.diff(aText, bText))
            case .run_js:
                let out = await ScriptRunner.run(a.s("code"), input: a.s("input"))
                return .text(out.clamped(20_000))
            case .web_fetch:
                let r = try await WebOps.fetch(a.s("url"), maxChars: a.i("max_chars", 8000))
                let title = r.title.isEmpty ? a.s("url") : r.title
                return .text("【\(title)】\n\n\(r.text)")
            case .web_search:
                if settings.searchEndpoint.isEmpty {
                    return .text(try await WebOps.search(a.s("query"), count: a.i("count", 8)))
                }
                return .text(try await WebOps.customSearch(endpoint: settings.searchEndpoint,
                                                            key: EchoSecrets.searchKey,
                                                            query: a.s("query")))
            case .table_to_csv:
                var text = a.s("text")
                if text.isEmpty, !a.s("name").isEmpty { text = try FileStore.shared.read(a.s("name")) }
                guard !text.isEmpty else { return .text("没给表格内容") }
                return .text(TextOps.tableToCSV(text, sep: a.s("sep")))
            case .date_calc:
                return .text(DateCalc.run(a.s("op"), a.s("base"), a.d("amount"), a.s("unit"), a.s("format")))
            case .unit_convert:
                return .text(UnitConverter.convert(a.d("value"), a.s("from"), a.s("to"), a.s("group")))
            case .make_qrcode:
                let data = try ImageOps.qr(a.s("text"), size: a.i("size", 512))
                let name = a.s("save_as", "qrcode.png")
                let url = try FileStore.shared.writeData(name, data)
                return .file(name: url.lastPathComponent, url: url, bytes: data.count,
                             preview: "二维码内容：\(a.s("text").clamped(120))", added: 1, removed: 0)
            case .ocr_image:
                return .text(try await ImageOps.ocr(path: a.s("name")))
            case .ask_user:
                return .text("（由运行时接管，不应到这里）")
            }
        } catch let e as ToolFailure {
            return .text("失败：\(e.message)")
        } catch let e as FileStoreError {
            return .text("失败：\(e.localizedDescription)")
        } catch {
            return .text("失败：工具执行出错 — \(error.localizedDescription)")
        }
    }
}
