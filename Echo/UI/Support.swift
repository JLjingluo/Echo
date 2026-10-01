import SwiftUI
import UIKit
import SwiftData

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255; a = Double(v & 0xFF) / 255
        default:
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255; a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    static let bubble = Color(hex: "4D6BFE")
    static let softText = Color(hex: "8A8F99")
    static let cardBG = Color(.secondarySystemGroupedBackground)
    static let codeBG = Color(.systemGroupedBackground)
}

enum Theme {
    static let accent = Color(hex: "4D6BFE")
    static let radius: CGFloat = 14
}

struct CopyLabel: View {
    let text: String
    let systemImage: String
    @State private var copied = false

    var body: some View {
        Button {
            Notifier.copy(text)
            copied = true
            Notifier.shared.tap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: copied ? "checkmark" : systemImage)
                if copied { Text("已复制") }
            }
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

struct CodeBlock: View {
    let code: String
    let language: String
    var onSave: (String, String) -> Void = { _, _ in }

    @State private var wrapped = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: language.isEmpty ? "text" : language)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button { wrapped.toggle() } label: {
                    EchoIcon("text.alignleft", size: 15)
                        .foregroundStyle(wrapped ? Color.primary : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    Notifier.copy(code)
                    copied = true
                } label: {
                    HStack(spacing: 4) {
                        EchoIcon(copied ? "checkmark" : "doc.on.doc", size: 15)
                        Text(copied ? "已复制" : "复制").font(.caption)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button("存为文件", systemImage: "square.and.arrow.down") {
                        onSave(code, language)
                    }
                    Button("分享", systemImage: "square.and.arrow.up") {
                        ShareHelper.share(items: [code])
                    }
                } label: {
                    EchoIcon("ellipsis", size: 15)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.5)

            Group {
                if wrapped {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoM.codeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EchoM.codeRadius, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 0.5)
        )
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

enum ShareHelper {
    @MainActor
    static func share(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                    width: 0, height: 0)
        }
        top.present(vc, animated: true)
    }
}

struct FileExporter: UIViewControllerRepresentable {
    let urls: [URL]
    let onDone: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDone: (Bool) -> Void
        init(onDone: @escaping (Bool) -> Void) { self.onDone = onDone }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onDone(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDone(false)
        }
    }
}

extension ChatSession {
    var orderedMessages: [ChatMessage] { messages.sorted { $0.createdAt < $1.createdAt } }

    var previewText: String { orderedMessages.last?.text ?? "" }
}

extension ChatMessage {
    var runItems: [RunItem] {
        if blocks.isEmpty {
            return [RunItem(kind == .user ? .user : .text, order: 1, text: text, status: .done)]
        }
        return sortedBlocks.map { RunItem(block: $0) }
    }

    private var kind: BlkKind { role == .user ? .user : .text }
}

extension RunItem {
    init(block b: MsgBlock) {
        self.init(id: b.id.uuidString, b.kind, order: b.order, text: b.text, title: b.title,
                  status: ItemStatusLive(rawValue: b.statusRaw) ?? .done, path: b.path,
                  language: b.language, steps: b.steps,
                  argsDisplay: b.kind == .tool ? b.path : "",
                  startedAt: b.startedAt, endedAt: b.endedAt)
        if b.kind == .file {
            file = RunFile(name: b.title, path: b.path,
                           size: (try? Data(contentsOf: URL(fileURLWithPath: b.path)).count) ?? 0,
                           preview: b.text)
        }
        if b.kind == .tool {
            call = ToolCallView(id: b.id.uuidString, name: b.title, argsJSON: b.path,
                                result: b.text,
                                status: ItemStatus(rawValue: b.statusRaw) ?? .done,
                                startedAt: b.startedAt, endedAt: b.endedAt)
        }
    }
}
