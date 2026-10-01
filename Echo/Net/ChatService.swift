import Foundation

enum ChatError: LocalizedError {
    case noKey(String)
    case badURL(String)
    case http(Int, String)
    case empty
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noKey(let v): return "还没填 \(v) 的 API Key。打开设置填好再回来。"
        case .badURL(let s): return "Base URL 解析失败：\(s)"
        case .http(let code, let body): return "接口报错 \(code)：\(body.prefix(500))"
        case .empty: return "模型没返回内容，可能额度用尽或模型名不对。"
        case .cancelled: return "已停止。"
        }
    }
}

struct ChatService {
    let settings: AppSettings
    let apiKey: String

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 1800
        c.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    static func applyAuth(_ req: inout URLRequest, provider: ProviderKind, key: String) {
        switch provider {
        case .openai:
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    func url(for baseURL: String) -> URL? {
        settings.provider.resolvedChatURL(base: baseURL)
    }

    func stream(_ req: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        if !req.stream { return buffered(req) }
        return AsyncThrowingStream(StreamEvent.self, bufferingPolicy: .unbounded) { cont in
            let worker = Task {
                do {
                    guard let url = url(for: req.baseURL) else {
                        throw ChatError.badURL(req.baseURL)
                    }
                    let r = Self.makeRequest(url: url, provider: settings.provider,
                                             key: apiKey, body: req.bodyData())
                    let (bytes, response) = try await Self.session.bytes(for: r)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        throw ChatError.http(http.statusCode, body)
                    }
                    var decoder = StreamDecoder(provider: settings.provider)
                    var stopped = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty || t.hasPrefix(":") || t.hasPrefix("event:") { continue }
                        guard t.hasPrefix("data:") else { continue }
                        let payload = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                        else { continue }
                        for e in decoder.feed(obj) {
                            if case .stop = e { stopped = true }
                            cont.yield(e)
                        }
                    }
                    if !stopped { cont.yield(.stop(reason: "end")) }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in worker.cancel() }
        }
    }

    private func buffered(_ req: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream(StreamEvent.self, bufferingPolicy: .unbounded) { cont in
            let worker = Task {
                do {
                    let reply = try await next(req)
                    if !reply.reasoning.isEmpty { cont.yield(.reasonDelta(reply.reasoning)) }
                    if !reply.text.isEmpty { cont.yield(.textDelta(reply.text)) }
                    for c in reply.calls {
                        cont.yield(.callStart(id: c.id, name: c.name))
                        cont.yield(.callArgs(id: c.id, delta: c.arguments))
                    }
                    cont.yield(.usage(prompt: reply.prompt, completion: reply.completion))
                    cont.yield(.stop(reason: reply.stop))
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in worker.cancel() }
        }
    }

    func next(_ req: ChatRequest) async throws -> ChatReply {
        guard let url = url(for: req.baseURL) else { throw ChatError.badURL(req.baseURL) }
        let r = Self.makeRequest(url: url, provider: settings.provider, key: apiKey, body: req.bodyData())
        let (data, response) = try await Self.session.data(for: r)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ChatError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ChatError.empty
        }
        return Self.parseWhole(obj, provider: settings.provider)
    }

    static func makeRequest(url: URL, provider: ProviderKind, key: String, body: Data) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 300
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuth(&r, provider: provider, key: key)
        r.httpBody = body
        return r
    }

    static func parseWhole(_ obj: [String: Any], provider: ProviderKind) -> ChatReply {
        var reply = ChatReply()
        switch provider {
        case .openai:
            if let u = obj["usage"] as? [String: Any] {
                reply.prompt = u["prompt_tokens"] as? Int ?? 0
                reply.completion = u["completion_tokens"] as? Int ?? 0
            }
            let choice = (obj["choices"] as? [[String: Any]])?.first
            let msg = choice?["message"] as? [String: Any] ?? [:]
            reply.text = msg["content"] as? String ?? ""
            reply.reasoning = (msg["reasoning_content"] as? String) ?? (msg["reasoning"] as? String) ?? ""
            if let calls = msg["tool_calls"] as? [[String: Any]] {
                reply.calls = calls.compactMap { c in
                    let fn = c["function"] as? [String: Any] ?? [:]
                    let name = fn["name"] as? String ?? ""
                    guard !name.isEmpty else { return nil }
                    return AssistCall(id: c["id"] as? String ?? "call-\(UUID().uuidString.prefix(8))",
                                      name: name,
                                      arguments: fn["arguments"] as? String ?? "{}")
                }
            }
            reply.stop = choice?["finish_reason"] as? String ?? "stop"
        case .anthropic:
            if let u = obj["usage"] as? [String: Any] {
                reply.prompt = u["input_tokens"] as? Int ?? 0
                reply.completion = u["output_tokens"] as? Int ?? 0
            }
            for b in (obj["content"] as? [[String: Any]]) ?? [] {
                switch b["type"] as? String {
                case "text": reply.text += b["text"] as? String ?? ""
                case "thinking": reply.reasoning += b["thinking"] as? String ?? ""
                case "tool_use":
                    var args = "{}"
                    if let input = b["input"] as? [String: Any],
                       let d = try? JSONSerialization.data(withJSONObject: input) {
                        args = String(decoding: d, as: UTF8.self)
                    }
                    reply.calls.append(AssistCall(id: b["id"] as? String ?? "call-\(UUID().uuidString.prefix(8))",
                                                  name: b["name"] as? String ?? "",
                                                  arguments: args))
                default: break
                }
            }
            reply.stop = obj["stop_reason"] as? String ?? "end_turn"
        }
        return reply
    }
}

struct ChatReply {
    var text: String = ""
    var reasoning: String = ""
    var calls: [AssistCall] = []
    var prompt: Int = 0
    var completion: Int = 0
    var stop: String = "stop"

    var wantsTool: Bool { !calls.isEmpty || stop == "tool_calls" }
}
