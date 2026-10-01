import Foundation

final class StreamDecoder {
    private let provider: ProviderKind
    private var openAIIds: [Int: String] = [:]
    private var anthIds: [Int: String] = [:]
    private var anthStarted: [Int: Bool] = [:]

    init(provider: ProviderKind) { self.provider = provider }

    func feed(_ obj: [String: Any]) -> [StreamEvent] {
        switch provider {
        case .openai: return openAI(obj)
        case .anthropic: return anthropic(obj)
        }
    }

    private func openAI(_ obj: [String: Any]) -> [StreamEvent] {
        var out: [StreamEvent] = []
        if let e = obj["error"] as? [String: Any] {
            out.append(.serverError((e["message"] as? String) ?? String(decoding: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(), as: UTF8.self)))
            return out
        }
        if let u = obj["usage"] as? [String: Any] {
            out.append(.usage(prompt: u["prompt_tokens"] as? Int ?? 0,
                              completion: u["completion_tokens"] as? Int ?? 0))
        }
        guard let choices = obj["choices"] as? [[String: Any]], let ch = choices.first else { return out }
        let delta = ch["delta"] as? [String: Any] ?? [:]
        if let r = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String), !r.isEmpty {
            out.append(.reasonDelta(r))
        }
        if let c = delta["content"] as? String, !c.isEmpty { out.append(.textDelta(c)) }
        if let calls = delta["tool_calls"] as? [[String: Any]] {
            for call in calls {
                let idx = call["index"] as? Int ?? 0
                let fn = call["function"] as? [String: Any] ?? [:]
                let inlineId = call["id"] as? String
                if let id = inlineId, !id.isEmpty {
                    openAIIds[idx] = id
                    out.append(.callStart(id: id, name: fn["name"] as? String ?? ""))
                }
                if let a = fn["arguments"] as? String, !a.isEmpty {
                    let id = inlineId?.isEmpty == false ? inlineId! : (openAIIds[idx] ?? "")
                    if openAIIds[idx] == nil { openAIIds[idx] = id }
                    out.append(.callArgs(id: id, delta: a))
                }
            }
        }
        if let fr = ch["finish_reason"] as? String, !fr.isEmpty { out.append(.stop(reason: fr)) }
        return out
    }

    private func anthropic(_ obj: [String: Any]) -> [StreamEvent] {
        var out: [StreamEvent] = []
        let type = obj["type"] as? String ?? ""
        switch type {
        case "message_start":
            if let m = obj["message"] as? [String: Any], let u = m["usage"] as? [String: Any] {
                out.append(.usage(prompt: u["input_tokens"] as? Int ?? 0, completion: 0))
            }
        case "content_block_start":
            let idx = obj["index"] as? Int ?? 0
            if let b = obj["content_block"] as? [String: Any], b["type"] as? String == "tool_use" {
                let id = b["id"] as? String ?? "call-\(idx)"
                anthIds[idx] = id
                anthStarted[idx] = true
                out.append(.callStart(id: id, name: b["name"] as? String ?? ""))
            }
        case "content_block_delta":
            let idx = obj["index"] as? Int ?? 0
            let dl = obj["delta"] as? [String: Any] ?? [:]
            switch dl["type"] as? String {
            case "text_delta":
                if let t = dl["text"] as? String, !t.isEmpty { out.append(.textDelta(t)) }
            case "thinking_delta":
                if let t = dl["thinking"] as? String, !t.isEmpty { out.append(.reasonDelta(t)) }
            case "input_json_delta":
                if let p = dl["partial_json"] as? String, !p.isEmpty {
                    out.append(.callArgs(id: anthIds[idx] ?? "", delta: p))
                }
            default: break
            }
        case "message_delta":
            if let u = obj["usage"] as? [String: Any], let n = u["output_tokens"] as? Int {
                out.append(.usage(prompt: 0, completion: n))
            }
            if let sr = (obj["delta"] as? [String: Any])?["stop_reason"] as? String {
                out.append(.stop(reason: sr))
            }
        case "message_stop":
            out.append(.stop(reason: "end_turn"))
        case "error":
            let e = obj["error"] as? [String: Any] ?? [:]
            out.append(.serverError((e["message"] as? String) ?? "未知接口错误"))
        default:
            break
        }
        return out
    }
}
