import SwiftUI

struct ItemRow: View {
    let item: RunItem
    var onSaveCode: (String, String) -> Void = { _, _ in }
    var onOpenFile: (RunFile) -> Void = { _ in }

    var body: some View {
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
                EchoIcon(expanded ? "chevron.down" : "chevron.right", size: 10, weight: .semibold)
                    .frame(width: 10)
            }
            if live {
                ProgressView().controlSize(.mini).frame(width: 18, height: 18)
            } else {
                EchoIcon(symbol, size: 15).frame(width: 18)
            }
            Text(title)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let accessory {
                EchoIcon(accessory, size: 14)
            }
        }
        .foregroundStyle(failed ? Color.red : Color.primary)
        .frame(minHeight: EchoM.markerHeight)
        .contentShape(Rectangle())
    }
}

struct MarkerSeparator: View {
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

struct CodePanel: View {
    let label: String
    let code: String
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    private var display: String {
        code.count > 200_000 ? String(code.prefix(200_000)) : code
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(label).font(.system(.caption, design: .monospaced))
                Spacer()
                Button {
                    Notifier.copy(display)
                    copied = true
                } label: {
                    EchoIcon(copied ? "checkmark" : "doc.on.doc", size: 15)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .task(id: copied) {
                    guard copied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
            .padding(.leading, 12)
            .foregroundStyle(.secondary)
            .background(.quaternary.opacity(0.3))

            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Text(display)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(320, max(76, CGFloat(display.components(separatedBy: "\n").count) * 19 + 24)))
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct UserCard: View {
    let item: RunItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !item.images.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(item.images.enumerated()), id: \.offset) { _, d in
                            if let img = UIImage(data: d) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 96, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
                Text(item.text)
                    .font(.body)
                    .foregroundStyle(EchoTheme.primaryText(scheme))
                    .textSelection(.enabled)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 12)
                    .background(EchoTheme.rowFill(scheme),
                                in: RoundedRectangle(cornerRadius: EchoM.bubbleRadius,
                                                     style: .continuous))
            }
        }
    }
}

struct TextBody: View {
    let item: RunItem
    var onSave: (String, String) -> Void = { _, _ in }

    var body: some View {
        if item.isReasoning {
            ReasonRow(text: item.text, live: item.status == .running)
        } else if item.isStepHeader {
            MarkerRow(title: String(item.text.dropFirst(2)), symbol: "arrow.right.circle",
                      live: item.status == .running)
        } else {
            VStack(alignment: .leading, spacing: EchoM.blockSpacing) {
                ForEach(Array(CodeSplitter.segments(item.text).enumerated()), id: \.offset) { _, seg in
                    if seg.kind == .code {
                        CodeBlock(code: seg.body, language: seg.lang, onSave: onSave)
                    } else {
                        MarkdownView(text: seg.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CodeBody: View {
    let item: RunItem
    var onSave: (String, String) -> Void

    var body: some View {
        CodeBlock(code: item.text, language: item.language, onSave: onSave)
    }
}

struct ReasonRow: View {
    let text: String
    var live: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                MarkerRow(title: live ? "推理中…" : "推理过程", symbol: "sparkles",
                          expanded: open, live: live)
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "已展开" : "已折叠")
            if open {
                MarkdownView(text: text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
                    .transition(.identity)
            }
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                MarkerRow(title: title, symbol: symbol, expanded: open,
                          failed: failed, live: item.status == .running,
                          accessory: item.call?.duration)
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "已展开" : "已折叠")
            if open {
                VStack(spacing: 0) {
                    if !args.isEmpty { CodePanel(label: "参数", code: args) }
                    if !result.isEmpty {
                        if !args.isEmpty { Spacer().frame(height: 8) }
                        CodePanel(label: "结果", code: result)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }

    private var title: String {
        let label = ToolID(rawValue: name)?.label ?? ""
        return label.isEmpty ? name : "\(name) · \(label)"
    }

    private var symbol: String {
        (ToolID(rawValue: name) ?? .read_file).icon
    }
}

struct FileRow: View {
    let item: RunItem
    var onOpen: (RunFile) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let f = item.file {
            Button { onOpen(f) } label: {
                HStack(spacing: 8) {
                    EchoIcon(icon(f.ext), size: 18).foregroundStyle(.secondary)
                    Text(f.ext.uppercased())
                        .font(.caption2)
                        .padding(5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    Text(f.name)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("+\(f.added)").font(.system(.caption, design: .monospaced)).foregroundStyle(.green)
                    if f.removed > 0 {
                        Text("−\(f.removed)").font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
                    }
                    EchoIcon("arrow.up.right", size: 12).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: EchoM.rowHeight)
                .background(Color(uiColor: .secondarySystemBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHint("打开文件预览")
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        EchoSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("执行计划")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Group {
                            switch s.status {
                            case .done: EchoIcon("checkmark.circle.fill", size: 16)
                            case .running: ProgressView().controlSize(.small).frame(width: 16, height: 16)
                            case .failed: EchoIcon("x.circle.fill", size: 16)
                            case .cancelled: EchoIcon("minus.circle", size: 16)
                            default: EchoIcon("circle", size: 16)
                            }
                        }
                        .foregroundStyle(color(s.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(i + 1). \(s.title)")
                                .font(.body)
                                .strikethrough(s.status == .done, color: .secondary)
                            if !s.detail.isEmpty {
                                Text(s.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                            if !s.note.isEmpty, s.status == .done {
                                Text(s.note).font(.caption).foregroundStyle(.green).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(_ s: ItemStatus) -> Color {
        switch s {
        case .done: return .green
        case .running: return EchoTheme.primaryText(scheme)
        case .failed: return .red
        default: return Color.secondary.opacity(0.5)
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
            return "Key 不对或没权限。点顶部「厂商 · 模型」重新粘贴 Key。"
        }
        if text.contains("403") { return "这个 Key 没有调用该模型的权限。" }
        if text.contains("404") { return "Base URL 或模型名不对（404）。" }
        if text.contains("429") { return "被限流了，等一会儿再试。" }
        if text.contains("额度") || low.contains("insufficient") { return "账户额度或余额不足。" }
        return text.components(separatedBy: "：").first ?? text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                MarkerRow(title: brief, symbol: "exclamationmark.triangle", expanded: open,
                          failed: true)
            }
            .buttonStyle(.plain)
            if open {
                CodePanel(label: "原始返回", code: text)
                    .padding(.leading, 24)
            }
        }
    }
}
