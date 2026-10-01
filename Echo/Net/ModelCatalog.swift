import Foundation

struct ModelEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var owner: String
    var created: Date

    init(id: String, owner: String = "", created: Date = .distantPast) {
        self.id = id
        self.owner = owner
        self.created = created
    }
}

enum ModelCatalog {
    struct Snapshot: Codable {
        var fetchedAt: Date
        var models: [ModelEntry]
    }

    private static let nonChatMarkers = [
        "embedding", "embed", "rerank", "moderation", "tts", "text-to-speech",
        "speech", "audio", "asr", "whisper", "transcribe", "stt", "voice",
        "image", "video", "sora", "seedream", "wanx", "wan2", "flux", "dall",
        "dalle", "ocr", "realtime", "livetranslate", "qwen-mt", "clip-",
        "bge-", "gte-", "mm-embed", "stable-diffusion", "kolors", "hunyuan3d",
        "3d", "background-removal", "face", "senime", "paddle", "yi-vl",
    ]

    static let nonChatOverride = ["qwen-vl", "glm-4v", "moonshot-v1-8k-vision",
                                  "doubao-vision", "doubao-1-5-vision", "gemini",
                                  "gpt-4o", "claude", "kimi-latest", "hunyuan-vision"]

    static func isChatModel(_ raw: String) -> Bool {
        let m = raw.lowercased()
        guard !m.isEmpty else { return false }
        if nonChatOverride.contains(where: { m.contains($0) }) { return true }
        for k in nonChatMarkers where m.contains(k) { return false }
        return true
    }

    static func listURL(base raw: String, provider: ProviderKind) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { s = provider.defaultBaseURL }
        switch provider {
        case .openai:
            let suffix = "/chat/completions"
            if s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
            if s.hasSuffix("/models") { return URL(string: s) }
            return URL(string: s + "/models")
        case .anthropic:
            if s.hasSuffix("/messages") { s = String(s.dropLast("/messages".count)) }
            if s.hasSuffix("/v1") { return URL(string: s + "/models") }
            return URL(string: s + "/v1/models")
        }
    }

    static func fetch(base: String, provider: ProviderKind, key: String) async throws -> [ModelEntry] {
        guard let url = listURL(base: base, provider: provider) else { throw ChatError.badURL(base) }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.timeoutInterval = 40
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        ChatService.applyAuth(&r, provider: provider,
                              key: key.trimmingCharacters(in: .whitespacesAndNewlines))
        let (data, response) = try await ChatService.session.data(for: r)
        if let h = response as? HTTPURLResponse, h.statusCode >= 400 {
            throw ChatError.http(h.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw ChatError.empty }
        return parse(obj)
    }

    static func parse(_ obj: Any) -> [ModelEntry] {
        var arr: [Any] = []
        if let a = obj as? [Any] {
            arr = a
        } else if let d = obj as? [String: Any] {
            for k in ["data", "models", "result", "body", "items", "endpoints"] {
                if let a = d[k] as? [Any] { arr = a; break }
            }
        }
        var out: [ModelEntry] = []
        var seen = Set<String>()
        let iso = ISO8601DateFormatter()
        for e in arr {
            var id = ""
            var owner = ""
            var created = Date.distantPast
            if let s = e as? String {
                id = s
            } else if let d = e as? [String: Any] {
                for k in ["id", "name", "model", "model_id", "value", "endpoint"] {
                    if let v = d[k] as? String, !v.isEmpty { id = v; break }
                }
                for k in ["owned_by", "owner", "vendor", "publisher", "provider"] {
                    if let v = d[k] as? String, !v.isEmpty { owner = v; break }
                }
                if let n = (d["created"] as? NSNumber)?.doubleValue {
                    created = Date(timeIntervalSince1970: n)
                } else if let s = d["created_at"] as? String {
                    if let n = Double(s) { created = Date(timeIntervalSince1970: n) }
                    else if let dt = iso.date(from: s) { created = dt }
                }
            }
            let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(ModelEntry(id: t, owner: owner, created: created))
        }
        return out.sorted {
            if $0.created != $1.created { return $0.created > $1.created }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    private static func storeKey(_ vendorID: String) -> String { "echo.models.v1." + vendorID }

    static func load(vendorID: String) -> Snapshot? {
        guard let d = UserDefaults.standard.data(forKey: storeKey(vendorID)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: d)
    }

    static func save(vendorID: String, _ models: [ModelEntry]) {
        let s = Snapshot(fetchedAt: .now, models: models)
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: storeKey(vendorID))
        }
    }

    static func clear(vendorID: String) {
        UserDefaults.standard.removeObject(forKey: storeKey(vendorID))
    }
}
