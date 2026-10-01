import Foundation

enum Planner {
    static func plannerSystem(toolNames: [String]) -> String {
        let tools = toolNames.isEmpty
            ? "（当前没有可用工具，只能直接回答）"
            : toolNames.joined(separator: ", ")
        return """
        你是手机本地 AI 工作台的任务规划器。把用户目标拆成 1 到 6 个可执行步骤。

        这台手机上真实可用的工具只有：\(tools)
        规划只能依赖这些工具。不要规划装依赖、跑命令行、执行 Python、访问电脑文件这类手机上做不到的事。

        只输出 JSON，不要任何多余文字，不要用代码块包裹，格式严格如下：
        {"steps":[{"title":"不超过 14 字的动词短语","detail":"给执行器的具体指令，写清要用哪个工具、产出什么文件"}]}

        简单闲聊或一句话就能答的目标，输出只含一步：
        {"steps":[{"title":"直接回答","detail":"不需要工具，直接给出答案"}]}
        """
    }

    static func parseSteps(_ raw: String) -> [StepState] {
        guard let blob = firstObject(raw), let d = blob.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let arr = obj["steps"] as? [[String: Any]] else { return [] }
        var out: [StepState] = []
        for (i, item) in arr.prefix(8).enumerated() {
            let title = (item["title"] as? String) ?? (item["name"] as? String)
                ?? (item["step"] as? String) ?? ""
            let detail = (item["detail"] as? String) ?? (item["desc"] as? String)
                ?? (item["instruction"] as? String) ?? (item["content"] as? String) ?? ""
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            out.append(StepState(id: i + 1, title: t.clamped(40), detail: detail.clamped(400)))
        }
        return out
    }

    static func executorSystem(settings: AppSettings, goal: String, steps: [StepState],
                               index: Int, record: [String]) -> String {
        let toolLines = ToolKit.allowedTools(settings)
            .map { "- \($0.rawValue)（\($0.label)）" }.joined(separator: "\n")
        let plan = steps.enumerated()
            .map { i, s in "\(i + 1). \(s.title)" + (s.detail.isEmpty ? "" : " — \(s.detail)") }
            .joined(separator: "\n")
        let done = record.isEmpty ? "（还没有已完成的步骤）" : record.joined(separator: "\n")
        let step = steps[index]
        return """
        你是运行在 iPhone 本地的执行代理，现在只负责执行第 \(index + 1) 步。

        总目标：\(goal)

        完整计划：
        \(plan)

        已完成步骤与产出：
        \(done)

        当前步骤：\(step.title)
        步骤说明：\(step.detail)

        可用工具：
        \(toolLines)

        硬性规则：
        1. 需要工具就真实发起调用，绝对不要用文字描述「我已经写好了文件」。
        2. 任何要交给用户的文件都必须用 write_file 落地，文件名带正确扩展名，只写相对文件名。
        3. 互不依赖的调用可以一次并行发出，有依赖必须分开。
        4. 精确计算、批量文本处理一律用 run_js，不要心算。
        5. 这一步做完就用一两句话说明结果（做了什么、产出哪些文件名），然后停下，不要越界执行后面的步骤。
        6. 工具报错时先看清原因再换做法，不要原样重试第三次。
        7. 真的缺关键信息、猜错会让结果完全不对时，用 ask_user 当面问用户；能合理推断的不要问。
        8. 回复用中文。
        """
    }

    static let summariseSystem = """
    你是 iPhone 本地 AI 工作台的收尾助手，所有步骤已经执行完。基于执行记录给用户写最终回复：
    1. 先用一句话说结论。
    2. 列出产出的文件（原始文件名 + 用途），提醒文件已存在手机本地工作区，可导出到「文件」App。
    3. 需要用户配合的点（换模型、缺 key、需要联网）单独列出。
    4. 不要重复粘贴执行日志，不要把文件里的长内容再抄一遍，最多摘 10 行。
    用中文。
    """

    static func directSystem(settings: AppSettings) -> String {
        settings.systemPrompt + """

        当前模型不支持工具调用，直接给出完整可用的回答，不要提工具。
        """
    }

    private static func firstObject(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
        }
        guard let open = t.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = open
        while i < t.endIndex {
            let c = t[i]
            if escaped {
                escaped = false
            } else if c == "\\" && inString {
                escaped = true
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == "{" { depth += 1 }
                if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(t[open...i]) }
                }
            }
            i = t.index(after: i)
        }
        return nil
    }
}
