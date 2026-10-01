import Foundation

struct ToolSchema: Sendable {
    let name: String
    let description: String
    let rawJSON: String

    init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.rawJSON = (try? String(data: JSONSerialization.data(withJSONObject: parameters),
                                    encoding: .utf8)) ?? "{}"
    }

    var parameters: [String: Any] { JSONHelper.dict(rawJSON) }
}

struct AssistCall: Sendable, Equatable {
    var id: String
    var name: String
    var arguments: String
}

struct OutMsg: Sendable {
    var role: MsgRole
    var text: String
    var images: [Data] = []
    var calls: [AssistCall] = []
    var toolCallId: String = ""
    var toolName: String = ""

    static func user(_ t: String, images: [Data] = []) -> OutMsg { OutMsg(role: .user, text: t, images: images) }
    static func assistant(_ t: String, calls: [AssistCall] = []) -> OutMsg { OutMsg(role: .assistant, text: t, calls: calls) }
    static func tool(_ id: String, name: String, result: String) -> OutMsg {
        OutMsg(role: .tool, text: result, toolCallId: id, toolName: name)
    }
    static func plan(_ t: String) -> OutMsg { OutMsg(role: .plan, text: t) }
}

enum StreamEvent: Sendable {
    case textDelta(String)
    case reasonDelta(String)
    case callStart(id: String, name: String)
    case callArgs(id: String, delta: String)
    case usage(prompt: Int, completion: Int)
    case stop(reason: String)
    case serverError(String)
}

struct ChatRequest: Sendable {
    var system: String
    var messages: [OutMsg]
    var tools: [ToolSchema]
    var model: String
    var temperature: Double
    var maxTokens: Int
    var stream: Bool
    var thinking: Bool
    var provider: ProviderKind
    var baseURL: String
    var vendorID: String = ""

    init(base settings: AppSettings, model: String? = nil) {
        system = ""
        messages = []
        tools = []
        self.model = model ?? settings.model
        temperature = settings.temperature
        maxTokens = settings.maxTokens
        stream = settings.stream
        thinking = settings.deepThink
        provider = settings.provider
        baseURL = settings.trimmedBaseURL
        vendorID = settings.vendorID
    }

    func openaiBody() -> [String: Any] {
        var msgs: [[String: Any]] = []
        if !system.isEmpty { msgs.append(["role": "system", "content": system]) }
        for m in messages {
            var d: [String: Any] = [:]
            switch m.role {
            case .user:
                d["role"] = "user"
                d["content"] = OpenAIPayload.userContent(m)
            case .assistant:
                d["role"] = "assistant"
                if m.calls.isEmpty {
                    d["content"] = m.text
                } else {
                    d["content"] = m.text.isEmpty ? NSNull() : m.text
                    d["tool_calls"] = m.calls.map { c -> [String: Any] in
                        ["id": c.id, "type": "function",
                         "function": ["name": c.name, "arguments": c.arguments.isEmpty ? "{}" : c.arguments]]
                    }
                }
            case .tool:
                d["role"] = "tool"
                d["tool_call_id"] = m.toolCallId
                d["content"] = m.text
            case .plan:
                d["role"] = "user"
                d["content"] = m.text
            }
            msgs.append(d)
        }
        var body: [String: Any] = ["model": model, "messages": msgs, "stream": stream]
        let m = model.lowercased()
        let noTemp = m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") || m.contains("gpt-5")
        if noTemp {
            body["max_completion_tokens"] = maxTokens
        } else {
            body["temperature"] = thinking ? 1.0 : temperature
            body["max_tokens"] = maxTokens
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { t -> [String: Any] in
                ["type": "function", "function": ["name": t.name, "description": t.description,
                                                  "parameters": t.parameters]]
            }
            body["tool_choice"] = "auto"
            body["parallel_tool_calls"] = true
        }
        if thinking && m.contains("deepseek") && !m.contains("reasoner") {
            body["thinking"] = ["type": "enabled"]
        }
        if thinking && m.contains("qwen") { body["enable_thinking"] = true }
        if stream {
            body["stream_options"] = ["include_usage": true]
        }
        return body
    }

    func anthropicBody() -> [String: Any] {
        var msgs: [[String: Any]] = []
        for m in messages {
            switch m.role {
            case .user:
                var blocks: [[String: Any]] = []
                for d in m.images {
                    blocks.append(["type": "image", "source": ["type": "base64",
                                                               "media_type": "image/jpeg",
                                                               "data": d.base64EncodedString()]])
                }
                if !m.text.isEmpty { blocks.append(["type": "text", "text": m.text]) }
                msgs.append(["role": "user", "content": blocks])
            case .assistant:
                var blocks: [[String: Any]] = []
                if !m.text.isEmpty { blocks.append(["type": "text", "text": m.text]) }
                for c in m.calls {
                    blocks.append(["type": "tool_use", "id": c.id, "name": c.name,
                                   "input": JSONHelper.dict(c.arguments)])
                }
                if blocks.isEmpty { blocks.append(["type": "text", "text": " "]) }
                msgs.append(["role": "assistant", "content": blocks])
            case .tool:
                let block: [String: Any] = ["type": "tool_result", "tool_use_id": m.toolCallId,
                                            "content": m.text]
                if let last = msgs.last, (last["role"] as? String) == "user",
                   var arr = last["content"] as? [[String: Any]],
                   arr.last?["type"] as? String == "tool_result" {
                    arr.append(block)
                    msgs[msgs.count - 1] = ["role": "user", "content": arr]
                } else {
                    msgs.append(["role": "user", "content": [block]])
                }
            case .plan:
                msgs.append(["role": "user", "content": [["type": "text", "text": m.text]]])
            }
        }
        var body: [String: Any] = [
            "model": model,
            "messages": msgs,
            "max_tokens": thinking ? max(8192, maxTokens) : maxTokens,
            "stream": stream,
        ]
        if !system.isEmpty { body["system"] = system }
        if !thinking { body["temperature"] = temperature }
        if !tools.isEmpty {
            body["tools"] = tools.map { t -> [String: Any] in
                ["name": t.name, "description": t.description, "input_schema": t.parameters]
            }
        }
        if thinking {
            body["thinking"] = ["type": "enabled", "budget_tokens": max(2048, maxTokens / 2)]
        }
        return body
    }

    func bodyData() -> Data {
        let raw = provider == .openai ? openaiBody() : anthropicBody()
        return (try? JSONSerialization.data(withJSONObject: raw)) ?? Data()
    }

    func urlRequest(key: String) -> URLRequest? {
        guard let url = provider.resolvedChatURL(base: baseURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 300
        switch provider {
        case .openai:
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        req.httpBody = bodyData()
        return req
    }
}

enum JSONHelper {
    static func dict(_ json: String) -> [String: Any] {
        let s = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d),
              let m = o as? [String: Any] else { return [:] }
        return m
    }

    static func string(_ json: String) -> String {
        String(data: JSONSerialization.data(withJSONObject: [json]), encoding: .utf8) ?? "\"\(json)\""
    }

    static func pretty(_ json: String) -> String {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d),
              let p = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])
        else { return json }
        return String(decoding: p, as: UTF8.self)
    }
}

enum OpenAIPayload {
    static func userContent(_ m: OutMsg) -> Any {
        if m.images.isEmpty { return m.text }
        var blocks: [[String: Any]] = []
        for d in m.images {
            blocks.append(["type": "image_url",
                           "image_url": ["url": "data:image/jpeg;base64," + d.base64EncodedString()]])
        }
        if !m.text.isEmpty { blocks.append(["type": "text", "text": m.text]) }
        return blocks
    }
}
