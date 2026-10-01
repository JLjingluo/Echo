import Foundation
import SwiftData

enum History {
    static func build(from session: ChatSession, limit: Int) -> (msgs: [OutMsg], trimmed: Bool) {
        let keep: [ChatMessage] = session.orderedMessages.filter {
            ($0.roleRaw == MsgRole.user.rawValue || $0.roleRaw == MsgRole.assistant.rawValue)
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let trimmed = keep.count > limit
        let use = Array(keep.suffix(limit))
        let mapped = use.map { m -> OutMsg in
            m.roleRaw == MsgRole.user.rawValue
                ? .user(m.text)
                : .assistant(m.text)
        }
        return (mapped, trimmed)
    }

    static func filesSummary(from session: ChatSession) -> [RunFile] {
        var out: [RunFile] = []
        for m in session.orderedMessages {
            for b in m.sortedBlocks where b.kind == .file {
                let s = b.fileStats
                out.append(RunFile(name: b.title, path: b.path, size: s?.s ?? 0,
                                   preview: b.text, added: s?.a ?? 0, removed: s?.r ?? 0))
            }
        }
        return out
    }
}
