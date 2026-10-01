import Foundation

struct VendorPreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let provider: ProviderKind
    let baseURL: String
    let models: [String]
    var thinkingModels: [String] = []
    var visionModels: [String] = []
    let keyURL: String
    var note: String = ""
}

let vendorPresets: [VendorPreset] = [
    VendorPreset(
        id: "deepseek", name: "DeepSeek", provider: .openai,
        baseURL: "https://api.deepseek.com/v1",
        models: ["deepseek-chat", "deepseek-reasoner"],
        thinkingModels: ["deepseek-reasoner"],
        keyURL: "https://platform.deepseek.com/api_keys",
        note: "reasoner 不支持工具调用，Agent 模式请用 deepseek-chat"),
    VendorPreset(
        id: "openai", name: "OpenAI / ChatGPT", provider: .openai,
        baseURL: "https://api.openai.com/v1",
        models: ["gpt-4.1-mini", "gpt-4o", "gpt-4o-mini", "o4-mini", "gpt-5"],
        thinkingModels: ["o4-mini", "gpt-5"],
        visionModels: ["gpt-4o", "gpt-4.1", "gpt-5", "o4-mini"],
        keyURL: "https://platform.openai.com/api-keys"),
    VendorPreset(
        id: "anthropic", name: "Anthropic Claude", provider: .anthropic,
        baseURL: "https://api.anthropic.com",
        models: ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"],
        thinkingModels: ["claude-sonnet-4-5", "claude-opus-4-1"],
        visionModels: ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"],
        keyURL: "https://console.anthropic.com/settings/keys"),
    VendorPreset(
        id: "qwen", name: "通义千问 (阿里云百炼)", provider: .openai,
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        models: ["qwen-plus", "qwen-turbo", "qwen-max", "qwen3-max", "qwen-vl-max"],
        thinkingModels: ["qwen3-max", "qwen-plus"],
        visionModels: ["qwen-vl-max", "qwen-vl-plus"],
        keyURL: "https://bailian.console.aliyun.com/#/api-key",
        note: "国际区把 baseURL 换成 https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
    VendorPreset(
        id: "kimi", name: "Kimi (月之暗面)", provider: .openai,
        baseURL: "https://api.moonshot.cn/v1",
        models: ["kimi-k2-0905-preview", "kimi-latest", "moonshot-v1-8k", "moonshot-v1-32k"],
        visionModels: ["kimi-vision-latest", "moonshot-v1-8k-vision-preview"],
        keyURL: "https://platform.moonshot.cn/console/api-keys",
        note: "国际区换成 https://api.moonshot.ai/v1"),
    VendorPreset(
        id: "zhipu", name: "智谱 GLM", provider: .openai,
        baseURL: "https://open.bigmodel.cn/api/paas/v4",
        models: ["glm-4.6", "glm-4.5-air", "glm-4-plus", "glm-4v-plus"],
        thinkingModels: ["glm-4.6", "glm-4.5"],
        visionModels: ["glm-4v-plus", "glm-4.5v"],
        keyURL: "https://open.bigmodel.cn/usercenter/apikeys"),
    VendorPreset(
        id: "doubao", name: "豆包 (火山方舟)", provider: .openai,
        baseURL: "https://ark.cn-beijing.volces.com/api/v3",
        models: ["doubao-seed-1-6-250615", "doubao-pro-32k-240821", "doubao-1-5-vision-pro-32k-250115"],
        visionModels: ["doubao-1-5-vision-pro-32k-250115"],
        keyURL: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey",
        note: "方舟要用推理服务 ID(endpoint)，模型名填 ep-xxxx 也行"),
    VendorPreset(
        id: "hunyuan", name: "腾讯混元", provider: .openai,
        baseURL: "https://api.hunyuan.cloud.tencent.com/v1",
        models: ["hunyuan-turbos-latest", "hunyuan-large", "hunyuan-vision"],
        keyURL: "https://console.cloud.tencent.com/hunyuan/api-key"),
    VendorPreset(
        id: "minimax", name: "MiniMax", provider: .openai,
        baseURL: "https://api.minimaxi.com/v1",
        models: ["MiniMax-M2", "abab6.5s-chat"],
        keyURL: "https://www.minimaxi.com/platform/api-key",
        note: "旧域名 https://api.minimax.chat/v1 也可用，看你 key 开的哪个区"),
    VendorPreset(
        id: "siliconflow", name: "硅基流动 SiliconFlow", provider: .openai,
        baseURL: "https://api.siliconflow.cn/v1",
        models: ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen3-235B-A22B", "Pro/deepseek-ai/DeepSeek-V3.2"],
        keyURL: "https://cloud.siliconflow.cn/account/ak"),
    VendorPreset(
        id: "step", name: "阶跃星辰 Step", provider: .openai,
        baseURL: "https://api.stepfun.com/v1",
        models: ["step-3.5-flash", "step-2-16k"],
        keyURL: "https://platform.stepfun.com/interface-key"),
    VendorPreset(
        id: "openrouter", name: "OpenRouter (聚合)", provider: .openai,
        baseURL: "https://openrouter.ai/api/v1",
        models: ["deepseek/deepseek-chat", "anthropic/claude-sonnet-4.5", "openai/gpt-4o-mini"],
        keyURL: "https://openrouter.ai/settings/keys"),
    VendorPreset(
        id: "groq", name: "Groq", provider: .openai,
        baseURL: "https://api.groq.com/openai/v1",
        models: ["llama-3.3-70b-versatile", "gpt-oss-120b"],
        keyURL: "https://console.groq.com/keys"),
    VendorPreset(
        id: "mistral", name: "Mistral", provider: .openai,
        baseURL: "https://api.mistral.ai/v1",
        models: ["mistral-large-latest", "mistral-small-latest"],
        keyURL: "https://console.mistral.ai/api-keys"),
    VendorPreset(
        id: "xai", name: "xAI Grok", provider: .openai,
        baseURL: "https://api.x.ai/v1",
        models: ["grok-3", "grok-3-mini"],
        thinkingModels: ["grok-3-mini"],
        keyURL: "https://console.x.ai"),
    VendorPreset(
        id: "gemini", name: "Google Gemini (兼容口)", provider: .openai,
        baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
        models: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"],
        thinkingModels: ["gemini-2.5-pro"],
        visionModels: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"],
        keyURL: "https://aistudio.google.com/apikey"),
    VendorPreset(
        id: "custom", name: "自定义（任何 OpenAI 兼容口）", provider: .openai,
        baseURL: "",
        models: [],
        keyURL: "",
        note: "自己填 Base URL，末尾不要带斜杠"),
]

func presets(for provider: ProviderKind) -> [VendorPreset] {
    vendorPresets.filter { $0.provider == provider }
}

func findPreset(_ id: String) -> VendorPreset? {
    vendorPresets.first { $0.id == id }
}
