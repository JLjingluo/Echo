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

    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    init(rgba: UInt32) {
        self.init(.sRGB,
                  red: Double((rgba >> 24) & 0xFF) / 255,
                  green: Double((rgba >> 16) & 0xFF) / 255,
                  blue: Double((rgba >> 8) & 0xFF) / 255,
                  opacity: Double(rgba & 0xFF) / 255)
    }
}

enum Ench {
    static let text = Color(light: Color(rgba: 0x0606_06ff), dark: Color(rgba: 0xfbfb_fcff))
    static let secondaryText = Color(light: Color(rgba: 0x6b6e_7bff), dark: Color(rgba: 0x9294_a0ff))
    static let tertiaryText = Color(light: Color(rgba: 0x6b6e_7bff), dark: Color(rgba: 0x6d70_7dff))
    static let background = Color(light: .white, dark: Color(rgba: 0x1819_1dff))
    static let secondaryBackground = Color(light: Color(rgba: 0xf7f7_f9ff), dark: Color(rgba: 0x2526_2aff))
    static let link = Color(light: Color(rgba: 0x2c65_cfff), dark: Color(rgba: 0x4c8e_f8ff))
    static let border = Color(light: Color(rgba: 0xe4e4_e8ff), dark: Color(rgba: 0x4244_4eff))
    static let divider = Color(light: Color(rgba: 0xd0d0_d3ff), dark: Color(rgba: 0x3334_38ff))
    static let cardFill = Color(light: Color(rgba: 0xf7f7_f9ff), dark: Color(rgba: 0x2526_2aff))
    static let cardStroke = Color(light: Color(rgba: 0xe4e4_e8ff), dark: Color(rgba: 0x4244_4eff)).opacity(0.35)
    static let brand = [Color(hex: "4285f4"), Color(hex: "9b72cb"),
                        Color(hex: "d96570"), Color(hex: "d96570")]
    static var brandGradient: LinearGradient {
        LinearGradient(colors: brand, startPoint: .leading, endPoint: .trailing)
    }
    static let body = CGFloat(14)
}

struct GrowingButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.2 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

extension View {
    func showIf(_ bool: Bool) -> some View {
        modifier(ConditionalView(show: bool))
    }
}

struct ConditionalView: ViewModifier {
    let show: Bool
    func body(content: Content) -> some View {
        Group {
            if show { content } else { EmptyView() }
        }
    }
}

struct RunningBorder: ViewModifier {
    @State private var rotation = 0.0
    var animated: Bool

    func body(content: Content) -> some View {
        if animated {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [.indigo, .blue, .red, .orange, .indigo]),
                                center: .center,
                                startAngle: .degrees(rotation),
                                endAngle: .degrees(rotation + 360)
                            ).opacity(0.5),
                            lineWidth: 3.5
                        )
                )
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func runningBorder(animated: Bool) -> some View {
        modifier(RunningBorder(animated: animated))
    }
}

extension Date {
    func daysAgoString() -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let day = cal.startOfDay(for: self)
        let diff = cal.dateComponents([.day], from: day, to: today).day ?? 0
        switch diff {
        case 0: return "今天"
        case 1: return "昨天"
        case 2: return "前天"
        default:
            if diff < 7 { return "\(diff) 天前" }
            let f = DateFormatter()
            f.dateFormat = "M 月 d 日"
            return f.string(from: self)
        }
    }
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

    @State private var copied = false

    private var lang: String {
        let l = language.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? "code" : l.components(separatedBy: " ").first ?? "code"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: lang)
                    .font(.system(size: 13, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Notifier.copy(code)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .padding(7)
                }
                .buttonStyle(GrowingButton())
                Menu {
                    Button("存为文件", systemImage: "square.and.arrow.down") {
                        onSave(code, lang)
                    }
                    Button("分享", systemImage: "square.and.arrow.up") {
                        ShareHelper.share(items: [code])
                    }
                } label: {
                    Image(systemName: "ellipsis").padding(7)
                }
                .buttonStyle(GrowingButton())
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Ench.secondaryBackground)

            Divider().overlay(Ench.divider)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: Ench.body * 0.85, design: .monospaced))
                    .lineSpacing(Ench.body * 0.225)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
            }
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
