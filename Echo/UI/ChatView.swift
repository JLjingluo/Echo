import SwiftUI
import SwiftData

private struct TailFrameKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Bindable var session: ChatSession
    var onMenu: () -> Void

    @State private var draft = ""
    @State private var showWorkspace = false
    @State private var showSettings = false
    @State private var showModel = false
    @State private var speaking = false
    @State private var previewFile: RunFile?
    @State private var exportURLs: [URL] = []
    @State private var atBottom = true
    @State private var scrollTick = 0
    @State private var showDetails = false

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
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    EchoTheme.background(scheme)
                    if timeline.isEmpty {
                        EmptyState(onPick: { draft = $0 },
                                   openModel: { showModel = true })
                    } else {
                        timelineScroll(viewport: geo.size.height)
                    }
                    if !atBottom && !timeline.isEmpty {
                        Button { scrollTick += 1 } label: {
                            HStack(spacing: 5) {
                                EchoIcon("arrow.down", size: 13)
                                Text("到底部")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .glass(.capsule, interactive: true)
                            .frame(minHeight: EchoM.touch)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 2)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(session.title.isEmpty ? "新会话" : session.title)
            .navigationSubtitle(" ")
            .toolbarBackground(EchoTheme.background(scheme), for: .navigationBar)
            .tint(EchoTheme.controlFill(scheme))
            .toolbar { bar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                InputBar(text: $draft, session: session,
                         onOpenSettings: { showSettings = true })
                    .frame(maxWidth: EchoM.maxContentWidth)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(EchoTheme.background(scheme))
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

    @ToolbarContentBuilder
    private var bar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onMenu) {
                EchoIcon("sidebar.left", size: 19)
            }
            .accessibilityLabel("打开侧栏")
        }
        ToolbarItem(placement: .principal) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title.isEmpty ? "新会话" : session.title)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Button { showModel = true } label: {
                    HStack(spacing: 4) {
                        EchoIcon("sparkles", size: 11)
                        Text("\(app.vendorName) · \(app.settings.model)")
                            .font(.caption)
                            .lineLimit(1)
                        EchoIcon("chevron.down", size: 10, weight: .semibold)
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("厂商与模型")
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showWorkspace = true } label: { EchoIcon("folder", size: 19) }
                .accessibilityLabel("工作区文件")
            Menu {
                Button { showModel = true } label: { Label("厂商与模型", systemImage: "sparkles") }
                Button { showWorkspace = true } label: { Label("工作区文件", systemImage: "folder") }
                Button { exportAll() } label: { Label("导出全部文件到「文件」", systemImage: "square.and.arrow.up") }
                Button { clearLive() } label: { Label("清空执行过程", systemImage: "eraser") }
                Divider()
                Button(role: .destructive) { deleteSession() } label: { Label("删除会话", systemImage: "trash") }
            } label: {
                EchoIcon("ellipsis", size: 19)
            }
            .accessibilityLabel("会话菜单")
        }
    }

    private func timelineScroll(viewport: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EchoM.timelineSpacing) {
                    ForEach(timeline) { item in
                        ItemRow(item: item, onSaveCode: saveCode, onOpenFile: { previewFile = $0 })
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(item.id)
                    }
                    statusLine
                    runFooter
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .background {
                            GeometryReader { g in
                                Color.clear.preference(key: TailFrameKey.self,
                                                       value: g.frame(in: .global).minY)
                            }
                        }
                }
                .echoColumn(nil)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "echo.timeline")
            .onPreferenceChange(TailFrameKey.self) { y in
                atBottom = y < viewport + 60
            }
            .onChange(of: timeline.count) { _, _ in
                if atBottom { scrollTo(proxy) }
            }
            .onChange(of: timeline.last?.text.count ?? 0) { _, _ in
                if atBottom { scrollTo(proxy) }
            }
            .onChange(of: scrollTick) { _, _ in
                atBottom = true
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear { scrollTo(proxy) }
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
        case .planning: RunningLine(text: "正在拆解任务…")
        case .executing: RunningLine(text: "正在执行…")
        case .summarising: RunningLine(text: "正在整理结果…")
        case .awaiting: RunningLine(text: "计划已生成，等你确认", icon: "hand.raised")
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var runFooter: some View {
        if showsLive {
            VStack(alignment: .leading, spacing: 10) {
                if runtime.toolCount > 0 || runtime.thinkingCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showDetails.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            EchoIcon(showDetails ? "chevron.down" : "chevron.right", size: 10,
                                     weight: .semibold)
                                .frame(width: 10)
                            EchoIcon("hammer", size: 15).frame(width: 18)
                            Text("执行过程 · \(runtime.thinkingCount) 段思考 · \(runtime.toolCount) 次工具")
                                .font(.system(.subheadline, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.primary)
                        .frame(minHeight: EchoM.markerHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !files.isEmpty {
                    Button { showWorkspace = true } label: {
                        HStack(spacing: 8) {
                            EchoIcon("doc.text", size: 15).frame(width: 18).foregroundStyle(.secondary)
                            Text("\(files.count) 个文件")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("+\(files.reduce(0) { $0 + $1.added })")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.green)
                            if files.reduce(0, { $0 + $1.removed }) > 0 {
                                Text("−\(files.reduce(0) { $0 + $1.removed })")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                            EchoIcon("arrow.up.right", size: 12).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: EchoM.markerHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if runtime.phase == .done {
                    HStack(spacing: 2) {
                        Button { copyAnswer() } label: {
                            EchoIcon("doc.on.doc", size: 15).frame(width: 44, height: 44)
                        }
                        Button { shareAnswer() } label: {
                            EchoIcon("square.and.arrow.up", size: 15).frame(width: 44, height: 44)
                        }
                        Button { speakAnswer() } label: {
                            EchoIcon(speaking ? "stop.circle" : "speaker.wave.2", size: 15)
                                .frame(width: 44, height: 44)
                        }
                        Spacer(minLength: 8)
                        Text(runtime.usage.text)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.leading, -10)
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
        let urls: [URL] = files.map { URL(fileURLWithPath: $0.path) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        items.append(contentsOf: urls)
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

struct RunningLine: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                EchoIcon(icon, size: 15).frame(width: 18)
            } else {
                ProgressView().controlSize(.mini).frame(width: 18, height: 18)
            }
            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minHeight: EchoM.markerHeight)
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
