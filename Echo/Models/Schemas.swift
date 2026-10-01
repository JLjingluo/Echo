import Foundation
import SwiftData

enum MsgRole: String, Codable {
    case user, assistant, plan, tool
}

enum BlkKind: String, Codable {
    case user, text, code, tool, file, plan, image, error, note
}

enum ItemStatus: String, Codable {
    case pending, running, done, failed, cancelled
}

@Model
final class ChatSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var model: String
    var providerRaw: String
    @Relationship(deleteRule: .cascade) var messages: [ChatMessage] = []

    init(title: String = "新会话") {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.model = ""
        self.providerRaw = ProviderKind.openai.rawValue
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    var reasoning: String
    var createdAt: Date
    var runId: UUID?
    var blocks: [MsgBlock] = []

    init(role: MsgRole, text: String = "", reasoning: String = "") {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.reasoning = reasoning
        self.createdAt = .now
    }

    var role: MsgRole { MsgRole(rawValue: roleRaw) ?? .assistant }
    var sortedBlocks: [MsgBlock] { blocks.sorted { $0.order < $1.order } }
}

@Model
final class MsgBlock {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var order: Int
    var text: String
    var language: String
    var title: String
    var statusRaw: String
    var path: String
    var startedAt: Date
    var endedAt: Date
    var stepsJSON: String
    var metaJSON: String

    init(kind: BlkKind, order: Int, text: String = "", language: String = "",
         title: String = "", status: ItemStatus = .done, path: String = "",
         startedAt: Date = .now, endedAt: Date = .now, stepsJSON: String = "",
         metaJSON: String = "") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.order = order
        self.text = text
        self.language = language
        self.title = title
        self.statusRaw = status.rawValue
        self.path = path
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stepsJSON = stepsJSON
        self.metaJSON = metaJSON
    }

    var kind: BlkKind { BlkKind(rawValue: kindRaw) ?? .text }
    var status: ItemStatus { ItemStatus(rawValue: statusRaw) ?? .done }
    var steps: [StepState] {
        guard !stepsJSON.isEmpty, let d = stepsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StepState].self, from: d)) ?? []
    }

    var fileStats: (a: Int, r: Int, s: Int)? {
        guard !metaJSON.isEmpty, let d = metaJSON.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return (o["a"] as? Int ?? 0, o["r"] as? Int ?? 0, o["s"] as? Int ?? 0)
    }

    static func meta(added: Int, removed: Int, size: Int) -> String {
        let s = String(data: (try? JSONSerialization.data(withJSONObject:
            ["a": added, "r": removed, "s": size])) ?? Data(), encoding: .utf8) ?? ""
        return s
    }
}

struct StepState: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var title: String
    var detail: String
    var status: ItemStatus
    var note: String

    init(id: Int, title: String, detail: String = "", status: ItemStatus = .pending, note: String = "") {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.note = note
    }
}

struct ToolCallView: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var argsJSON: String
    var result: String
    var status: ItemStatus
    var startedAt: Date
    var endedAt: Date

    var duration: String {
        let s = max(0, endedAt.timeIntervalSince(startedAt))
        if s < 1 { return "<1s" }
        if s < 60 { return String(format: "%.1fs", s) }
        return String(format: "%.0fm%02.0fs", (s / 60).rounded(.down), s.truncatingRemainder(dividingBy: 60))
    }
}
