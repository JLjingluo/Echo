import SwiftUI

struct ItemRow: View {
    let item: RunItem
    var onSaveCode: (String, String) -> Void = { _, _ in }
    var onOpenFile: (RunFile) -> Void = { _ in }

    var body: some View {
        switch item.kind {
        case .user: UserCard(item: item)
        case .text: TextBody(item: item)
        case .code: CodeBody(item: item, onSave: onSaveCode)
        case .tool: ToolRow(item: item)
        case .file: FileRow(item: item, onOpen: onOpenFile)
        case .plan: PlanCard(steps: item.steps)
        case .error: ErrorRow(text: item.text)
        case .note: DividerLabel(text: item.text)
        case .image: EmptyView()
        }
    }
}

struct UserCard: View {
    let item: RunItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.text)
                .font(.system(size: 17))
                .lineSpacing(6)
                .textSelection(.enabled)
            if !item.images.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(item.images.enumerated()), id: \.offset) { _, d in
                        if let img = UIImage(data: d) {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F6F6F8"), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.6))
        .padding(.top, 6)
    }
}

struct TextBody: View {
    let item: RunItem

    var body: some View {
        if item.isReasoning {
            ReasonRow(text: item.text, live: item.status == .running)
        } else if item.isStepHeader {
            HStack(spacing: 7) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(item.text.dropFirst(2))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                if item.status == .running {
                    Spacer()
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(CodeSplitter.segments(item.text).enumerated()), id: \.offset) { _, seg in
                    if seg.kind == .code {
                        CodeBlock(code: seg.body, language: seg.lang)
                            .padding(.vertical, 6)
                    } else {
                        MarkdownView(text: seg.body)
                            .padding(.bottom, 6)
                    }
                }
                if item.status == .running {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            .opacity(0.9)
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "brain.head.profile").font(.system(size: 12))
                    Text(live ? "思考中…" : "思考过程")
                        .font(.system(size: 14))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .padding(.leading, 20)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ToolRow: View {
    let item: RunItem
    @State private var open = false

    var statusColor: Color {
        switch item.status {
        case .running: return Theme.accent
        case .done: return Color(hex: "2FA46B")
        case .failed: return Color(hex: "D9483B")
        case .cancelled: return .secondary
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if item.status == .running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: (ToolID(rawValue: item.call?.name ?? item.title) ?? .read_file).icon)
                            .font(.system(size: 13))
                    }
                    Text(item.call?.name ?? item.title)
                        .font(.system(size: 14.5, weight: .medium))
                    Text(ToolID(rawValue: item.call?.name ?? "")?.label ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let c = item.call, c.status == .done {
                        Text(c.duration).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Circle().fill(statusColor).frame(width: 5.5, height: 5.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 8) {
                    if let args = item.call?.argsJSON, !args.isEmpty {
                        labeled("参数", JSONHelper.pretty(args))
                    } else if !item.argsDisplay.isEmpty {
                        labeled("参数", JSONHelper.pretty(item.argsDisplay))
                    }
                    if let r = item.call?.result, !r.isEmpty {
                        labeled("结果", r)
                    } else if !item.text.isEmpty, item.text != item.title {
                        labeled("结果", item.text)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 1.5)
    }

    private func labeled(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v.count > 3000 ? String(v.prefix(3000)) + "\n…(截断)" : v)
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.codeBG, in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

struct FileRow: View {
    let item: RunItem
    var onOpen: (RunFile) -> Void

    var body: some View {
        if let f = item.file {
            Button { onOpen(f) } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon(f.ext))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(f.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text("+\(f.added)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "2FA46B"))
                    if f.removed > 0 {
                        Text("−\(f.removed)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "D9483B"))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Color(hex: "F6F6F8"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
    }

    private func icon(_ ext: String) -> String {
        switch ext {
        case "md", "txt", "log": return "doc.text"
        case "swift", "js", "ts", "py", "go", "rs", "java", "c", "h": return "chevron.left.forwardslash.chevron.right"
        case "html", "css": return "globe"
        case "json", "yml", "yaml", "toml", "ini": return "curlybraces"
        case "csv", "tsv", "xlsx": return "tablecells"
        case "png", "jpg", "jpeg", "gif", "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

struct PlanCard: View {
    let steps: [StepState]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { s in
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        switch s.status {
                        case .done: Image(systemName: "checkmark.circle.fill")
                        case .running: ProgressView().controlSize(.small)
                        case .failed: Image(systemName: "x.circle.fill")
                        case .cancelled: Image(systemName: "minus.circle")
                        default: Image(systemName: "circle")
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(color(s.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title)
                            .font(.system(size: 15, weight: .medium))
                            .strikethrough(s.status == .done, color: .secondary)
                        if !s.detail.isEmpty {
                            Text(s.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if !s.note.isEmpty, s.status == .done {
                            Text(s.note).font(.system(size: 12)).foregroundStyle(Color(hex: "2FA46B"))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F6F6F8"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, 4)
    }

    private func color(_ s: ItemStatus) -> Color {
        switch s {
        case .done: return Color(hex: "2FA46B")
        case .running: return Theme.accent
        case .failed: return Color(hex: "D9483B")
        default: return Color.secondary.opacity(0.5)
        }
    }
}

struct ErrorRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "D9483B"))
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Color(hex: "D9483B"))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(hex: "D9483B").opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
