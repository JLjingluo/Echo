import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var session: ChatSession
    var onMenu: () -> Void

    @State private var draft = ""
    @State private var showWorkspace = false
    @State private var showSettings = false
    @State private var showDetails = false
    @State private var speaking = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var previewFile: RunFile?
    @State private var exportURLs: [URL] = []
    @State private var atBottom = true

    private var runtime: AgentRuntime { app.runtime }

    private var showsLive: Bool {
        runtime.sessionId == session.id && !runtime.items.isEmpty && runtime.hasUnpersisted
    }

    private var shownMessages: [ChatMessage] {
        var ms = session.orderedMessages
        if showsLive, ms.last?.role == .user { ms.removeLast() }
        return ms
    }

    private var timeline: [RunItem] {
        var out: [RunItem] = []
        for m in shownMessages { out.append(contentsOf: m.runItems) }
        if showsLive {
            out.append(contentsOf: runtime.items.filter { showDetails || !isDetail($0) })
        }
        return out
    }

    private func isDetail(_ i: RunItem) -> Bool { i.kind == .tool || i.isReasoning }

    private var files: [RunFile] {
        showsLive ? runtime.runFiles : History.filesSummary(from: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if timeline.isEmpty {
                EmptyState(onPick: { draft = $0 }, openModel: { showSettings = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                timelineScroll
            }
            InputBar(text: $draft, session: session, onOpenSettings: { showSettings = true })
        }
        .background(Color(.systemBackground))
        .onAppear { runtime.persistIfNeeded(session: session, context: context) }
        .onChange(of: runtime.phase) { _, newPhase in
            guard newPhase == .done, app.settings.autoExport else { return }
            let urls = runtime.runFiles.map { URL(fileURLWithPath: $0.path) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { exportURLs = urls }
        }
        .sheet(isPresented: $showWorkspace) { WorkspaceView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $previewFile) { FilePreviewView(file: $0) }
        .alert("重命名会话", isPresented: $renaming) {
            TextField("标题", text: $newName)
            Button("好") { session.title = newName; try? context.save() }
            Button("取消", role: .cancel) {}
        }
        .modifier(ExportModifier(urls: $exportURLs))
    }

    private var timelineScroll: some View {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(timeline) { item in
                            ItemRow(item: item, onSaveCode: saveCode, onOpenFile: { previewFile = $0 })
                                .id(item.id)
                                .transition(.opacity)
                        }
                        statusLine
                        runFooter
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: timeline.count) { _, _ in
                    if atBottom { withAnimation(.linear(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                .onChange(of: timeline.last?.text.count ?? 0) { _, _ in
                    if atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            GlassIconButton(system: "line.3.horizontal", hint: "会话列表", action: onMenu)
            Spacer(minLength: 8)
            Menu {
                Button { showSettings = true } label: { Label("厂商与模型", systemImage: "sparkles") }
                Button { showWorkspace = true } label: { Label("工作区文件", systemImage: "folder") }
                Button { newName = session.title; renaming = true } label: { Label("重命名会话", systemImage: "pencil") }
                Button { exportAll() } label: { Label("导出全部文件到「文件」", systemImage: "square.and.arrow.up") }
                Button { clearLive() } label: { Label("清空执行过程", systemImage: "eraser") }
                Divider()
                Button(role: .destructive) { deleteSession() } label: { Label("删除会话", systemImage: "trash") }
            } label: {
                HStack(spacing: 6) {
                    Text("Echo")
                        .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    Text(app.vendorName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glass(.capsule)
                .contentShape(Capsule())
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runtime.phase {
        case .planning:
            RunningLine(text: "Agent 正在拆解任务…")
        case .executing:
            RunningLine(text: "Agent 正在处理任务…")
        case .summarising:
            RunningLine(text: "Agent 正在整理结果…")
        case .awaiting:
            RunningLine(text: "计划已生成，等你确认", icon: "hand.raised.fill")
        case .failed:
            EmptyView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var runFooter: some View {
        if showsLive {
            VStack(alignment: .leading, spacing: 10) {
                if runtime.toolCount > 0 || runtime.thinkingCount > 0 {
                    Button {
                        withAnimation(.snappy) { showDetails.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "pin.fill").font(.system(size: 12))
                            Text("\(runtime.thinkingCount) 段思考 · \(runtime.toolCount) 次工具调用")
                                .font(.system(size: 14.5, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(Color(hex: "D9483B"))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !files.isEmpty {
                    Button { showWorkspace = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.system(size: 14))
                            Text("\(files.count) 个文件")
                                .font(.system(size: 14.5))
                            Text("+\(files.reduce(0) { $0 + $1.added })")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(Color(hex: "2FA46B"))
                            Text("−\(files.reduce(0) { $0 + $1.removed })")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(Color(hex: "D9483B"))
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if runtime.phase == .done {
                    HStack(spacing: 22) {
                        Button { copyAnswer() } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 16))
                        }
                        Button { shareAnswer() } label: {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 16))
                        }
                        Button { speakAnswer() } label: {
                            Image(systemName: speaking ? "stop.circle.fill" : "speaker.wave.2")
                                .font(.system(size: 16))
                        }
                        Text(runtime.usage.text).font(.system(size: 12)).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copyAnswer() {
        Notifier.copy(timeline.filter { $0.kind == .text && !$0.isReasoning }
            .map(\.text).joined(separator: "\n\n"))
        Notifier.shared.tap()
    }

    private func shareAnswer() {
        let text = timeline.filter { $0.kind == .text && !$0.isReasoning }.map(\.text)
            .joined(separator: "\n\n")
        var items: [Any] = [text.isEmpty ? "（空）" : text]
        items.append(contentsOf: files.map { URL(fileURLWithPath: $0.path) }
            .filter { FileManager.default.fileExists(atPath: $0.path) })
        ShareHelper.share(items: items)
    }

    private func speakAnswer() {
        if speaking {
            Notifier.shared.stopSpeaking()
            speaking = false
        } else {
            let text = timeline.filter { $0.kind == .text && !$0.isReasoning }.map(\.text)
                .joined(separator: "\n")
            Notifier.shared.speak(text)
            speaking = true
        }
    }

    private func exportAll() {
        let urls = files.map(\.path).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        exportURLs = urls
    }

    private func clearLive() {
        runtime.persistIfNeeded(session: session, context: context)
        runtime.reset(for: session.id)
    }

    private func deleteSession() {
        runtime.persistIfNeeded(session: session, context: context)
        context.delete(session)
        try? context.save()
        onMenu()
    }

    private func saveCode(_ code: String, _ lang: String) {
        let ext = CodeLang.ext(lang)
        let name = "snippet-\(Int(Date.now.timeIntervalSince1970) % 100000).\(ext)"
        do {
            _ = try FileStore.shared.write(name, code)
            Notifier.shared.runDone(title: "已存为文件", body: name)
        } catch {
            Notifier.shared.runDone(title: "保存失败", body: error.localizedDescription)
        }
    }
}

struct RunningLine: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13))
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.system(size: 14.5)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct ExportModifier: ViewModifier {
    @Binding var urls: [URL]

    func body(content: Content) -> some View {
        content.overlay {
            if !urls.isEmpty {
                FileExporter(urls: urls) { _ in urls = [] }
                    .ignoresSafeArea()
            }
        }
    }
}

enum CodeLang {
    static func ext(_ lang: String) -> String {
        let map = ["javascript": "js", "typescript": "ts", "python": "py", "shell": "sh",
                   "bash": "sh", "objective-c": "m", "c++": "cpp", "markdown": "md",
                   "yaml": "yml", "jsonc": "json", "text": "txt", "plain": "txt"]
        let l = lang.lowercased().trimmingCharacters(in: .whitespaces)
        if l.isEmpty { return "txt" }
        return map[l] ?? l.components(separatedBy: " ").first ?? "txt"
    }
}
