import SwiftUI

struct ItemRow: View {
    let item: RunItem
    var isEditing = false
    var onSaveCode: (String, String) -> Void = { _, _ in }
    var onOpenFile: (RunFile) -> Void = { _ in }
    var onEdit: (RunItem) -> Void = { _ in }
    var onRegenerate: () -> Void = {}
    var onSpeak: (String) -> Void = { _ in }

    var body: some View {
        Group {
            switch item.kind {
            case .user: UserCard(item: item)
            case .text: TextBody(item: item, onSave: onSaveCode)
            case .code: CodeBody(item: item, onSave: onSaveCode)
            case .tool: ToolRow(item: item)
            case .file: FileRow(item: item, onOpen: onOpenFile)
            case .plan: PlanCard(steps: item.steps)
            case .error: ErrorRow(text: item.text)
            case .note: MarkerSeparator(title: item.text)
            case .image: EmptyView()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .contextMenu { menu }
        .runningBorder(animated: isEditing)
    }

    @ViewBuilder
    private var menu: some View {
        let body = item.call?.result ?? item.text
        if !body.isEmpty {
            Button { Notifier.copy(body) } label: { Label("复制", systemImage: "doc.on.doc") }
            Button { onSpeak(body) } label: { Label("朗读", systemImage: "speaker.wave.3.fill") }
        }
        if item.kind == .user {
            Button { onEdit(item) } label: { Label("编辑", systemImage: "pencil") }
            Button(action: onRegenerate) { Label("重新生成", systemImage: "arrow.clockwise") }
        }
    }
}

struct UserCard: View {
    let item: RunItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 8) {
                if !item.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(item.images.enumerated()), id: \.offset) { _, d in
                            if let img = UIImage(data: d) {
                                Image(uiImage: img)
                                    .resizable().scaledToFit()
                                    .frame(width: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
                MarkdownView(text: item.text)
            }
            .padding(14)
            .background(Ink.wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .sketch(seed: 61, corner: 18)
        }
    }
}

struct AssistantAvatar: View {
    var body: some View {
        Text("E")
            .font(EchoFont.wordmark(21))
            .foregroundStyle(Ench.text)
            .frame(width: 24, height: 24)
    }
}

struct TextBody: View {
    let item: RunItem
    var onSave: (String, String) -> Void = { _, _ in }

    var body: some View {
        if item.isReasoning {
            ReasonRow(text: item.text, live: item.status == .running,
                      seconds: max(0, item.endedAt.timeIntervalSince(item.startedAt)))
        } else if item.isStepHeader {
            MarkerRow(title: String(item.text.dropFirst(2)), symbol: "list.number",
                      live: item.status == .running)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                AssistantAvatar()
                    .offset(CGSize(width: 0, height: 6))
                VStack(alignment: .leading, spacing: Ench.body) {
                    ForEach(Array(CodeSplitter.segments(item.text).enumerated()), id: \.offset) { _, seg in
                        if seg.kind == .code {
                            CodeBlock(code: seg.body, language: seg.lang, onSave: onSave)
                        } else {
                            MarkdownView(text: seg.body)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                if item.status == .running {
                    ProgressView().controlSize(.mini)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct CodeBody: View {
    let item: RunItem
    var onSave: (String, String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            AssistantAvatar().offset(CGSize(width: 0, height: 6))
            CodeBlock(code: item.text, language: item.language, onSave: onSave)
                .padding(.leading, 8)
        }
    }
}

struct MarkerRow: View {
    let title: String
    var symbol: String = "hammer"
    var expanded: Bool?
    var failed: Bool = false
    var live: Bool = false
    var accessory: String?

    var body: some View {
        HStack(spacing: 8) {
            if let expanded {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 11)
            }
            if live {
                ProgressView().controlSize(.mini).frame(width: 18)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
            }
            Text(title)
                .font(.system(size: Ench.body))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let accessory {
                Text(accessory).font(.system(size: 11)).foregroundStyle(Ench.tertiaryText)
            }
        }
        .foregroundStyle(failed ? Color.red : Ench.text)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }
}

struct MarkerSeparator: View {
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Ench.divider).frame(height: 1)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Ench.secondaryText)
                .fixedSize()
            Rectangle().fill(Ench.divider).frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

struct CodePanel: View {
    let label: String
    let code: String
    @State private var copied = false

    private var display: String {
        code.count > 200_000 ? String(code.prefix(200_000)) : code
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Notifier.copy(display)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").padding(7)
                }
                .buttonStyle(GrowingButton())
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Ench.secondaryBackground)

            Divider().overlay(Ench.divider)

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Text(display)
                    .font(.system(size: Ench.body * 0.85, design: .monospaced))
                    .lineSpacing(Ench.body * 0.225)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(320, max(76, CGFloat(display.components(separatedBy: "\n").count) * 19 + 24)))
        }
        .background(Ench.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

struct ReasonRow: View {
    let text: String
    var live: Bool
    var seconds: Double = 0
    @State private var open = false

    private var summary: String {
        if live { return "思考中…" }
        if seconds < 1 { return "想了一下。" }
        if seconds < 60 { return "思考了 \(String(format: seconds < 10 ? "%.1f" : "%.0f", seconds)) 秒。" }
        return "思考了 \(Int(seconds / 60)) 分 \(Int(seconds.truncatingRemainder(dividingBy: 60))) 秒。"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Rectangle().fill(Ench.text).frame(width: 10)
            VStack(alignment: .leading, spacing: 8) {
                if open {
                    MarkdownView(text: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(summary)
                        .font(.system(size: Ench.body))
                        .foregroundStyle(Ench.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } }
    }
}

struct ToolRow: View {
    let item: RunItem
    @State private var open = false

    private var name: String { item.call?.name ?? item.title }
    private var failed: Bool { item.status == .failed }
    private var args: String {
        let a = item.call?.argsJSON ?? item.argsDisplay
        return a.isEmpty ? "" : JSONHelper.pretty(a)
    }
    private var result: String {
        let r = item.call?.result ?? item.text
        return r == item.title ? "" : r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                MarkerRow(title: title, symbol: symbol, expanded: open,
                          failed: failed, live: item.status == .running,
                          accessory: item.call?.duration)
            }
            .buttonStyle(GrowingButton())
            if open {
                VStack(spacing: 8) {
                    if failed, !result.isEmpty { ToolErrorBox(message: result) }
                    if !args.isEmpty { CodePanel(label: "参数", code: args) }
                    if !result.isEmpty, !failed { CodePanel(label: "结果", code: result) }
                }
                .padding(.leading, 29)
            }
        }
    }

    private var title: String {
        let raw = item.call?.argsJSON ?? item.argsDisplay
        guard let id = ToolID(rawValue: name) else { return name }
        return ToolSummary.title(id, args: raw)
    }

    private var symbol: String {
        (ToolID(rawValue: name) ?? .read_file).icon
    }
}

struct FileRow: View {
    let item: RunItem
    var onOpen: (RunFile) -> Void

    var body: some View {
        if let f = item.file {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                AssistantAvatar().offset(CGSize(width: 0, height: 6))
                VStack(alignment: .leading, spacing: 0) {
                    Button { onOpen(f) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(f.ext))
                                .font(.system(size: 15))
                                .foregroundStyle(Ench.secondaryText)
                            Text(f.name)
                                .font(.system(size: Ench.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text("+\(f.added)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(DiffTheme.addText)
                            if f.removed > 0 {
                                Text("−\(f.removed)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(DiffTheme.delText)
                            }
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Ench.tertiaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if f.isText {
                        Divider().overlay(Ench.divider)
                        DiffCard(file: f)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ench.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Ench.cardStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.leading, 8)
            }
        }
    }

    private func icon(_ ext: String) -> String {
        switch ext {
        case "md", "txt", "log": return "doc.text"
        case "js", "ts", "py", "go", "rs", "java", "c", "h", "swift", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "css", "svg", "xml": return "globe"
        case "json", "yml", "yaml", "toml", "ini": return "curlybraces"
        case "csv", "tsv", "xlsx": return "tablecells"
        case "png", "jpg", "jpeg", "gif", "pdf", "heic": return "doc.richtext"
        default: return "doc"
        }
    }
}

struct PlanCard: View {
    let steps: [StepState]

    private var doneCount: Int { steps.filter { $0.status == .done }.count }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            AssistantAvatar().offset(CGSize(width: 0, height: 6))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("执行计划")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ench.secondaryText)
                    Spacer()
                    Text("\(doneCount)/\(steps.count)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Ench.tertiaryText)
                        .monospacedDigit()
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Group {
                            switch s.status {
                            case .done: Image(systemName: "checkmark.circle.fill")
                            case .running: ProgressView().controlSize(.small).frame(width: 15, height: 15)
                            case .failed: Image(systemName: "x.circle.fill")
                            case .cancelled: Image(systemName: "minus.circle")
                            default: Image(systemName: "circle")
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(color(s.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(i + 1). \(s.title)")
                                .font(.system(size: Ench.body))
                                .strikethrough(s.status == .done, color: Ench.tertiaryText)
                            if !s.detail.isEmpty {
                                Text(s.detail).font(.system(size: 12))
                                    .foregroundStyle(Ench.secondaryText).lineLimit(2)
                            }
                            if !s.note.isEmpty, s.status == .done {
                                Text(s.note).font(.system(size: 11))
                                    .foregroundStyle(.green).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ench.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Ench.cardStroke, lineWidth: 1))
            .padding(.leading, 8)
        }
    }

    private func color(_ s: ItemStatus) -> Color {
        switch s {
        case .done: return .green
        case .running: return Ench.text
        case .failed: return .red
        default: return Ench.tertiaryText
        }
    }
}

struct ErrorRow: View {
    let text: String
    @State private var open = false

    private var brief: String {
        let low = text.lowercased()
        if low.contains("invalid_api_key") || low.contains("incorrect api key")
            || low.contains("apikey-error") || text.contains("401") {
            return "Key 不对或没权限。点顶部模型名重新粘贴 Key。"
        }
        if text.contains("403") { return "这个 Key 没有调用该模型的权限。" }
        if text.contains("404") { return "Base URL 或模型名不对（404）。" }
        if text.contains("429") { return "被限流了，等一会儿再试。" }
        if low.contains("insufficient") { return "账户额度或余额不足。" }
        return text.clamped(160)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(brief)
                    .foregroundColor(.red)
                    .font(.system(size: 16))
                Spacer()
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                MarkerRow(title: open ? "收起原始返回" : "查看原始返回",
                          symbol: "chevron.left.forwardslash.chevron.right", expanded: open)
                    .foregroundStyle(Ench.secondaryText)
            }
            .buttonStyle(.plain)
            if open {
                CodePanel(label: "原始返回", code: text)
            }
        }
    }
}

struct WorkGroupHeader: View {
    let text: String
    var chevronUp = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Ench.secondaryText)
                    .lineLimit(1)
                Image(systemName: chevronUp ? "chevron.up" : "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Ench.secondaryText)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(GrowingButton())
        .padding(.vertical, 8)
    }
}

struct ToolErrorBox: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DiffTheme.delText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(DiffTheme.delText)
                .lineLimit(6)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(DiffTheme.delFill))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(DiffTheme.delText.opacity(0.35), lineWidth: 1))
    }
}

struct DiffCard: View {
    let file: RunFile
    private let limit = 8

    @State private var lines: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Ench.tertiaryText)
                        .frame(width: 22, alignment: .trailing)
                    Text(l.isEmpty ? " " : "+ " + l)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DiffTheme.addText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DiffTheme.addFill)
            }
            if file.added > limit {
                Text("还有 \(file.added - limit) 行，点文件名看完整内容")
                    .font(.system(size: 11))
                    .foregroundStyle(Ench.tertiaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: file.path) { await load() }
    }

    private func load() async {
        guard lines.isEmpty else { return }
        let path = file.path
        lines = await Task.detached(priority: .userInitiated) { () -> [String] in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
            let text = String(decoding: data, as: UTF8.self)
            return Array(text.components(separatedBy: "\n").prefix(limit))
        }.value
    }
}
