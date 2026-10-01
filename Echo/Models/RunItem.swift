import Foundation
import SwiftUI

enum ItemStatusLive: String, Codable, Sendable {
    case pending, running, done, failed, cancelled, waitingApprove
}

struct RunFile: Identifiable, Equatable, Sendable, Codable {
    var id: String { path }
    let name: String
    let path: String
    let size: Int
    let preview: String
    var added: Int
    var removed: Int

    init(name: String, path: String, size: Int, preview: String, added: Int = 0, removed: Int = 0) {
        self.name = name
        self.path = path
        self.size = size
        self.preview = preview
        self.added = added
        self.removed = removed
    }

    var sizeText: String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }

    var ext: String { (path as NSString).pathExtension.lowercased() }
    var isText: Bool {
        ["md", "txt", "csv", "json", "swift", "js", "ts", "py", "html", "css", "yml", "yaml",
         "sh", "xml", "log", "ini", "toml", "sql", "c", "h", "java", "kt", "go", "rs"].contains(ext)
    }
}

struct RunItem: Identifiable, Equatable, Sendable, Codable {
    var id: String
    var kind: BlkKind
    var order: Int
    var text: String
    var language: String
    var title: String
    var status: ItemStatusLive
    var path: String
    var startedAt: Date
    var endedAt: Date
    var steps: [StepState]
    var call: ToolCallView?
    var file: RunFile?
    var images: [Data]
    var argsDisplay: String

    init(id: String? = nil, _ kind: BlkKind, order: Int, text: String = "",
         title: String = "", status: ItemStatusLive = .running, path: String = "",
         language: String = "", images: [Data] = [], steps: [StepState] = [],
         call: ToolCallView? = nil, file: RunFile? = nil, argsDisplay: String = "",
         startedAt: Date = .now, endedAt: Date = .now) {
        self.id = id ?? "\(kind.rawValue)-\(order)-\(UUID().uuidString.prefix(6))"
        self.kind = kind
        self.order = order
        self.text = text
        self.language = language
        self.title = title
        self.status = status
        self.path = path
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.steps = steps
        self.call = call
        self.file = file
        self.images = images
        self.argsDisplay = argsDisplay
    }

    static func == (lhs: RunItem, rhs: RunItem) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.status == rhs.status
            && lhs.steps == rhs.steps && lhs.call == rhs.call && lhs.order == rhs.order
    }

    var isReasoning: Bool { kind == .text && title == "思考" }
    var isStepHeader: Bool { kind == .text && text.hasPrefix("▸ ") }
}

struct RunUsage: Equatable, Sendable {
    var prompt = 0
    var completion = 0
    var total: Int { prompt + completion }
    var seconds: Double = 0

    var text: String {
        let s = seconds < 60 ? String(format: "%.1fs", seconds)
                             : String(format: "%.1fmin", seconds / 60)
        return "\(total) tokens · \(s)"
    }
}

enum RunPhase: String, Sendable {
    case idle, planning, awaiting, executing, summarising, done, failed, cancelled
}
