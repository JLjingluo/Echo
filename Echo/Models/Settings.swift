import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openai
    case anthropic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openai: return "OpenAI 兼容接口"
        case .anthropic: return "Anthropic 官方接口"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.deepseek.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "deepseek-chat"
        case .anthropic: return "claude-sonnet-4-5"
        }
    }

    var keyHeader: String {
        switch self {
        case .openai: return "Authorization"
        case .anthropic: return "x-api-key"
        }
    }

    func resolvedChatURL(base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        switch self {
        case .openai:
            return URL(string: s + "/chat/completions")
        case .anthropic:
            if s.hasSuffix("/v1") { return URL(string: s + "/messages") }
            return URL(string: s + "/v1/messages")
        }
    }
}

struct AppSettings: Codable, Equatable {
    var vendorID: String = "deepseek"
    var provider: ProviderKind = .openai
    var baseURL: String = "https://api.deepseek.com/v1"
    var model: String = "deepseek-chat"
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
    var systemPrompt: String = AppSettings.defaultSystemPrompt
    var stream: Bool = true
    var autoApprove: Bool = false
    var deepThink: Bool = false
    var historyLimit: Int = 40
    var enabledTools: [String] = ToolID.allCases.map(\.rawValue)
        .filter { $0 != ToolID.delete_file.rawValue }
    var maxTurnsPerStep: Int = 6
    var autoExport: Bool = false
    var haptics: Bool = true
    var searchEndpoint: String = ""
    var voiceLanguage: String = "zh-CN"

    static let defaultSystemPrompt = """
    你是 Echo，一个运行在 iPhone 本地的 AI 工作台。
    你可以直接调用手机上的工具：读写文件、处理文本、抓网页、搜索、跑 JavaScript、生成二维码、识图。
    规则：
    1. 需要用工具时只发工具调用，不要假装已经执行过。
    2. 产出文件一律用 write_file，文件名带正确扩展名，路径用相对文件名。
    3. 用户要多个文件就多次调用，不要合并成一个大文件除非内容本来是一体的。
    4. 只要你的回答里包含一个完整可用的文件（HTML 页面、JS/TS 脚本、CSS、JSON、Markdown、SVG、CSV、Python、Shell 等），
       就必须先调用 write_file 把它真正写进工作区，正文里只说结论和文件名，不要把整段代码再贴一遍。
       只有用户明确要「看代码」或代码片段不足一个文件时才贴在正文里。
    5. 正文里贴代码时，代码块的围栏必须标语言，文件名写在围栏上，例如 ```html index.html。
    6. 回答用中文，简洁，代码给完整可运行版本。
    """

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let v = try? c.decode(T.self, forKey: key) else { return fallback }
            return v
        }
        vendorID = d(.vendorID, "deepseek")
        provider = d(.provider, .openai)
        baseURL = d(.baseURL, "https://api.deepseek.com/v1")
        model = d(.model, "deepseek-chat")
        temperature = d(.temperature, 0.7)
        maxTokens = d(.maxTokens, 4096)
        systemPrompt = d(.systemPrompt, Self.defaultSystemPrompt)
        stream = d(.stream, true)
        autoApprove = d(.autoApprove, false)
        deepThink = d(.deepThink, false)
        historyLimit = d(.historyLimit, 40)
        enabledTools = d(.enabledTools, ToolID.allCases.map(\.rawValue)
            .filter { $0 != ToolID.delete_file.rawValue })
        maxTurnsPerStep = d(.maxTurnsPerStep, 6)
        autoExport = d(.autoExport, false)
        haptics = d(.haptics, true)
        searchEndpoint = d(.searchEndpoint, "")
        voiceLanguage = d(.voiceLanguage, "zh-CN")
    }

    var toolsEnabled: Set<String> { Set(enabledTools) }

    func toolAllowed(_ id: ToolID) -> Bool { enabledTools.contains(id.rawValue) }

    var vendor: VendorPreset? { findPreset(vendorID) }

    var modelSupportsVision: Bool {
        if let v = vendor?.visionModels, v.contains(model) { return true }
        let m = model.lowercased()
        return m.contains("vision") || m.contains("-vl") || m.contains("vl-")
            || m.contains("gemini") || m.contains("claude") || m.contains("gpt-4o")
            || m.contains("gpt-4.1") || m.contains("gpt-5") || m.contains("qwen3.5")
    }

    var modelIsReasoning: Bool {
        if let t = vendor?.thinkingModels, t.contains(model) { return true }
        let m = model.lowercased()
        return m.contains("reasoner") || m.contains("qwq") || m.hasPrefix("o1") || m.hasPrefix("o3")
    }

    var modelSupportsTools: Bool {
        !enabledTools.isEmpty && !NoToolMemory.contains(model)
    }

    var trimmedBaseURL: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? provider.defaultBaseURL : s
    }

}
