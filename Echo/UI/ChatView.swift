import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Bindable var session: ChatSession
    var onMenu: () -> Void
    var onNew: () -> Void = {}

    @State private var draft = ""
    @State private var editingText: String?
    @State private var showWorkspace = false
    @State private var showSettings = false
    @State private var showModel = false
    @State private var speaking = false
    @State private var previewFile: RunFile?
    @State private var exportURLs: [URL] = []
    @State private var expandedGroups: Set<String> = []
    @State private var reach = Reachability.shared

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
        if showsLive { out.append(contentsOf: runtime.items) }
        return out
    }

    private var nodes: [TimelineNode] {
        var out: [TimelineNode] = []
        var buf: [RunItem] = []
        func flush() {
            guard !buf.isEmpty else { return }
            let start = buf.map(\.startedAt).min() ?? .now
            let end = buf.map(\.endedAt).max() ?? .now
            let label = WorkDuration.text(end.timeIntervalSince(start))
            out.append(.group(WorkGroup(id: "grp-" + buf[0].id, items: buf, label: label)))
            buf = []
        }
        for item in timeline {
            if isDetail(item) {
                buf.append(item)
            } else {
                flush()
                out.append(.item(item))
            }
        }
        flush()
        return out
    }

    private func isDetail(_ i: RunItem) -> Bool { i.kind == .tool || i.isReasoning }

    private var files: [RunFile] {
        showsLive ? runtime.runFiles : History.filesSummary(from: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            if EchoState.storeDegraded {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text("数据库打不开，这次的内容关掉就没了。重装 App 可恢复。")
                        .font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(DiffTheme.delText)
                .padding(12)
                .background(DiffTheme.delFill)
            }
            if !reach.online {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash").font(.system(size: 13))
                    Text("没网。发出去的任务会等着，联网后重试。")
                        .font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(Ench.secondaryText)
                .padding(12)
                .background(Ench.secondaryBackground)
            }
            header.padding(.horizontal)
            if timeline.isEmpty {
                EmptyState(sendPrompt: { send(goal: $0, images: [], truncating: nil) })
            } else {
                timelineScroll
            }
            statusLine.padding()
            InputBar(text: $draft, editingText: $editingText, session: session,
                     onSend: { goal, images in send(goal: goal, images: images,
                                                    truncating: editingText) },
                     onStop: { runtime.cancel() },
                     onOpenSettings: { showSettings = true })
        }
        .padding(.bottom, 5)
        .background(Ench.background.ignoresSafeArea())
        .onAppear { runtime.persistIfNeeded(session: session, context: context) }
        .onChange(of: runtime.phase) { _, newPhase in
            guard newPhase == .done, app.settings.autoExport else { return }
            let urls = runtime.runFiles.map { URL(fileURLWithPath: $0.path) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { exportURLs = urls }
        }
        .sheet(isPresented: $showWorkspace) { WorkspaceView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showModel) { ModelPickerSheet() }
        .sheet(item: $previewFile) { FilePreviewView(file: $0) }
        .modifier(ExportModifier(urls: $exportURLs))
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22)
                    .foregroundColor(Color(.label))
            }
            .buttonStyle(GrowingButton())

            Spacer()

            ModelSelectorView(selected: app.settings.model, version: app.vendorName,
                              models: []) { showModel = true }

            Spacer()

            Button { showWorkspace = true } label: {
                Image(systemName: "folder")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21)
                    .foregroundColor(Color(.label))
            }
            .buttonStyle(GrowingButton())

            Button(action: onNew) {
                Image(systemName: "square.and.pencil")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22)
                    .foregroundColor(Color(.label))
            }
            .buttonStyle(GrowingButton())
        }
        .frame(height: 44)
    }

    private var timelineScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(nodes) { node in
                        switch node {
                        case .item(let item):
                            rowFor(item).id(item.id)
                        case .group(let g):
                            groupRow(g)
                        }
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onAppear { scrollTo(proxy) }
            .onChange(of: timeline.count) { _, _ in scrollTo(proxy) }
            .onChange(of: timeline.last?.text.count ?? 0) { _, _ in scrollTo(proxy) }
        }
    }

    private func rowFor(_ item: RunItem) -> some View {
        ItemRow(item: item,
                isEditing: editingText != nil && item.kind == .user
                    && item.text == editingText,
                onSaveCode: saveCode,
                onOpenFile: { previewFile = $0 },
                onEdit: { editingText = $0.text; draft = $0.text },
                onRegenerate: regenerate,
                onSpeak: { speak($0) })
    }

    private func regenerate() {
        guard !runtime.isBusy else { return }
        let ms = session.orderedMessages
        guard let idx = ms.lastIndex(where: { $0.role == .user }) else { return }
        let goal = ms[idx].text
        for m in ms[idx...] { context.delete(m) }
        try? context.save()
        send(goal: goal, images: [], truncating: nil)

    @ViewBuilder
    private func groupRow(_ g: WorkGroup) -> some View {
        let live = showsLive && g.items.contains { $0.status == .running }
        let open = live || expandedGroups.contains(g.id)
        VStack(spacing: 0) {
            WorkGroupHeader(text: live ? "正在工作…" : g.label, chevronUp: open) {
                if !live { toggle(g.id) }
            }
            if open {
                ForEach(g.items) { rowFor($0) }
                if !live {
                    WorkGroupHeader(text: "收起", chevronUp: true) {
                        toggle(g.id)
                    }
                }
            }
        }
        .id(g.id)
    }

    private func toggle(_ id: String) {
        var next = expandedGroups
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedGroups = next
        }
    }

    private func scrollTo(_ proxy: ScrollViewProxy) {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runtime.phase {
        case .planning:
            RunningLine(text: "正在拆解任务…")
        case .executing:
            RunningLine(text: "正在执行…")
        case .summarising:
            RunningLine(text: "正在整理结果…")
        case .awaiting:
            RunningLine(text: "计划已生成，等你确认", icon: "hand.raised.fill")
        case .failed:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private func send(goal raw: String, images: [Data], truncating: String?) {
        let goal = raw.trimmed
        guard !runtime.isBusy else { return }
        guard !goal.isEmpty || !images.isEmpty else { return }
        guard app.canSend else { showModel = true; return }
        if let t = truncating { truncateFrom(t) }
        let (hist, trimmed) = History.build(from: session, limit: app.historyLimit)
        var msgs = hist
        if trimmed { msgs.insert(.plan("（更早的对话内容已省略，只保留最近若干轮）"), at: 0) }
        let final = goal.isEmpty ? "看一下这张图，说说里面有什么，需要处理就处理。" : goal
        runtime.start(goal: final, images: images, history: msgs, settings: app.settings,
                      key: app.apiKey, session: session, context: context)
        if trimmed { runtime.addNote("上下文已压缩") }
        draft = ""
        editingText = nil
    }

    private func truncateFrom(_ text: String) {
        let ms = session.orderedMessages
        guard let idx = ms.lastIndex(where: { $0.role == .user && $0.text == text }) else { return }
        for m in ms[idx...] { context.delete(m) }
        try? context.save()
    }

    private func speak(_ body: String) {
        Notifier.shared.stopSpeaking()
        Notifier.shared.speak(body)
        speaking = true
    }

    private func saveCode(_ code: String, _ lang: String) {
        let ext = CodeLang.ext(lang)
        let name = CodeFiles.normalize("snippet-\(Int(Date.now.timeIntervalSince1970) % 100000)",
                                       ext: ext)
        do {
            _ = try FileStore.shared.write(name, code)
            runtime.addNote("已存为文件 \(name)")
            Notifier.shared.tap()
        } catch {
            Notifier.shared.runDone(title: "保存失败", body: error.localizedDescription)
        }
    }
}

struct WorkGroup: Identifiable {
    let id: String
    let items: [RunItem]
    let label: String
}

enum TimelineNode: Identifiable {
    case item(RunItem)
    case group(WorkGroup)

    var id: String {
        switch self {
        case .item(let i): return i.id
        case .group(let g): return g.id
        }
    }
}

struct ModelSelectorView: View {
    let selected: String
    let version: String
    var models: [String]
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(selected.isEmpty ? "选择模型" : selected)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(shortVendor)
                    .font(.system(size: 13))
                    .foregroundColor(Ench.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .showIf(!shortVendor.isEmpty)
                Image(systemName: "chevron.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 9)
                    .foregroundColor(Color(.label))
            }
            .frame(maxWidth: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(GrowingButton())
        .layoutPriority(1)
        .accessibilityLabel("厂商与模型")
    }

    private var shortVendor: String {
        version.components(separatedBy: CharacterSet(charactersIn: " (（")).first ?? version
    }
}

struct RunningLine: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(Ench.secondaryText)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.system(size: Ench.body)).foregroundStyle(Ench.secondaryText)
            Spacer()
        }
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
        let l = lang.lowercased().trimmed
        if l.isEmpty { return "txt" }
        return CodeFiles.extMap[l] ?? l.components(separatedBy: " ").first ?? "txt"
    }
}
