import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var showKey = false
    @State private var promptEditing = false
    @State private var showModel = false
    @State private var confirmSessions = false
    @State private var confirmFiles = false
    @State private var note = ""

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HandSectionHeader(text: "模型")
                    HandRow(glyph: .sparkle, title: "厂商与模型", value: modelSummary,
                            valueAccent: true) { showModel = true }
                    if !NoToolMemory.all.isEmpty {
                        HandRow(glyph: .close, title: "清除「不调工具」记忆（\(NoToolMemory.all.count)）",
                                divider: false) {
                            NoToolMemory.clear()
                            note = "已清除，下次会重新尝试调用工具"
                        }
                    }

                    HandSectionHeader(text: "外观")
                    HStack {
                        Text("配色").font(Hand.body(16)).foregroundStyle(Ink.line)
                        Spacer()
                        HandSegmented(options: EchoAppearance.allCases.map {
                            (label: $0.label, value: $0.rawValue)
                        }, selection: appearanceBinding)
                    }
                    .frame(minHeight: 50)

                    HandSectionHeader(text: "生成")
                    toggleRow("流式输出", isOn: $app.settings.stream)
                    HStack {
                        Text("深度思考").font(Hand.body(16)).foregroundStyle(Ink.line)
                        Spacer()
                        HandSegmented(options: [("自动", "auto"), ("强制开", "on"), ("强制关", "off")],
                                      selection: thinkingBinding)
                    }
                    .frame(minHeight: 50)
                    Text(thinkingLine)
                        .font(Hand.body(13))
                        .foregroundStyle(Ink.gray)
                        .padding(.bottom, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("温度").font(Hand.body(16)).foregroundStyle(Ink.line)
                            Spacer()
                            Text(String(format: "%.2f", app.settings.temperature))
                                .font(Hand.mono(14)).foregroundStyle(Ink.gray)
                        }
                        Slider(value: $app.settings.temperature, in: 0...2, step: 0.05)
                            .tint(Ink.accent)
                    }
                    .frame(minHeight: 50)
                    HandCounter(label: "最多生成长度", value: $app.settings.maxTokens,
                                range: 512...32000, step: 512, unit: " tok")

                    HandSectionHeader(text: "Agent 行为")
                    toggleRow("计划自动执行（关掉会先等你确认）", isOn: $app.settings.autoApprove)
                    HandCounter(label: "每步最多轮数", value: $app.settings.maxTurnsPerStep,
                                range: 2...12, step: 1)
                    HandCounter(label: "带上的历史条数", value: $app.settings.historyLimit,
                                range: 4...80, step: 2)
                    toggleRow("触感反馈", isOn: $app.settings.haptics)
                    toggleRow("跑完自动弹出导出", isOn: $app.settings.autoExport)

                    HandSectionHeader(text: "工具")
                    ForEach(Array(ToolID.allCases.enumerated()), id: \.offset) { i, t in
                        HStack(spacing: 12) {
                            HandIcon(glyph: toolGlyph(t), size: 18, color: Ink.gray,
                                     seed: UInt64(770 + i))
                                .frame(width: 24)
                            Text(t.label).font(Hand.body(16)).foregroundStyle(Ink.line)
                            Spacer()
                            HandToggle(isOn: toolBinding(t), seed: UInt64(780 + i))
                        }
                        .frame(minHeight: 46)
                        if i < ToolID.allCases.count - 1 {
                            SketchRect(seed: 791, corner: 1, wobble: 0.6)
                                .stroke(Ink.faint.opacity(0.4), lineWidth: 1)
                                .frame(height: 1)
                                .padding(.leading, 36)
                        }
                    }

                    HandSectionHeader(text: "人设与规则")
                    HandRow(glyph: .doc, title: "系统提示词",
                            value: "\(app.settings.systemPrompt.count) 字") { promptEditing = true }

                    HandSectionHeader(text: "联网搜索（可选）")
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("自定义搜索接口（仅 https）", text: $app.settings.searchEndpoint)
                            .font(Hand.mono(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .sketch(seed: 801, capsule: true, color: Ink.faint, width: 1.3)
                        HStack(spacing: 8) {
                            HandIcon(glyph: .sparkle, size: 15, color: Ink.gray, seed: 802)
                            Group {
                                if showKey {
                                    TextField("搜索接口 Key", text: searchKeyBinding)
                                } else {
                                    SecureField("搜索接口 Key", text: searchKeyBinding)
                                }
                            }
                            .font(Hand.mono(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button { showKey.toggle() } label: {
                                HandIcon(glyph: showKey ? .close : .search, size: 13,
                                         color: Ink.gray, seed: 803)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .sketch(seed: 804, capsule: true, color: Ink.faint, width: 1.3)
                        Text("留空则用内置的公共搜索引擎，可能被限流。Key 存在钥匙串，不进设置文件。")
                            .font(Hand.body(12))
                            .foregroundStyle(Ink.gray)
                    }

                    HandSectionHeader(text: "数据")
                    if EchoState.storeDegraded {
                        HStack(spacing: 8) {
                            HandIcon(glyph: .sparkle, size: 15, color: Ink.danger, seed: 810)
                            Text("数据库打不开，已切到内存模式：这次的记录关掉就没了。")
                                .font(Hand.body(13))
                                .foregroundStyle(Ink.danger)
                        }
                        .padding(.vertical, 6)
                    }
                    HandRow(glyph: .folder, title: "工作区占用",
                            value: ToolOutcome.sizeText(app.store.totalBytes()), divider: false)
                    HandRow(glyph: .trash, title: "清空所有会话", divider: false) {
                        confirmSessions = true
                    }
                    HandRow(glyph: .trash, title: "清空工作区文件", divider: false) {
                        confirmFiles = true
                    }
                    HandRow(glyph: .doc, title: "版本", value: AppVersion.text, divider: false)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Gutter.edge)
            }
            .scrollIndicators(.hidden)
            .background(Ink.paper.ignoresSafeArea())
            .overlay { PaperGrain(density: 400).ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.save(); dismiss() } label: {
                        Text("完成").font(Hand.body(16).weight(.semibold))
                            .foregroundStyle(Ink.line)
                    }
                }
            }
            .toolbarBackground(Ink.paper, for: .navigationBar)
            .onChange(of: app.settings) { _, _ in app.save() }
            .confirmationDialog("清空所有会话？", isPresented: $confirmSessions,
                                titleVisibility: .visible) {
                Button("清空", role: .destructive) { wipeSessions() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有聊天记录会立刻删除，撤销不了。")
            }
            .confirmationDialog("清空工作区文件？", isPresented: $confirmFiles,
                                titleVisibility: .visible) {
                Button("清空", role: .destructive) { wipeFiles() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("Agent 生成的文件会从本机删除。已经导出到「文件」App 的不受影响。")
            }
            .sheet(isPresented: $showModel) { ModelPickerSheet() }
            .sheet(isPresented: $promptEditing) { PromptEditor() }
            .safeAreaInset(edge: .bottom) { toast }
        }
    }

    @ViewBuilder private var toast: some View {
        if !note.isEmpty {
            Text(note)
                .font(Hand.pencil(17))
                .foregroundStyle(Ink.gray)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .sketch(seed: 820, capsule: true, color: Ink.faint, width: 1.3)
                .padding(.bottom, 8)
                .transition(.opacity)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Hand.body(16))
                .foregroundStyle(Ink.line)
                .lineLimit(2)
            Spacer()
            HandToggle(isOn: isOn, seed: 830)
        }
        .frame(minHeight: 50)
    }

    private var modelSummary: String {
        let m = app.settings.model
        return m.isEmpty ? app.vendorName : "\(app.vendorName) · \(m)"
    }

    private var thinkingLine: String {
        "\(app.settings.model)：\(app.settings.thinkingHint)"
    }

    private var appearanceBinding: Binding<String> {
        Binding(get: { app.appearance.rawValue },
                set: { app.appearance = EchoAppearance(rawValue: $0) ?? .system; app.save() })
    }

    private var thinkingBinding: Binding<String> {
        Binding(get: { app.settings.thinkingMode },
                set: { app.settings.thinkingMode = $0; app.save() })
    }

    private var searchKeyBinding: Binding<String> {
        Binding(get: { EchoSecrets.searchKey }, set: { EchoSecrets.searchKey = $0 })
    }

    private func toolGlyph(_ t: ToolID) -> HandGlyph {
        switch t {
        case .write_file: return .doc
        case .read_file: return .doc
        case .list_files: return .folder
        case .delete_file: return .trash
        case .move_file: return .folder
        case .text_ops: return .doc
        case .diff_text: return .doc
        case .run_js: return .sparkle
        case .web_fetch: return .search
        case .web_search: return .search
        case .table_to_csv: return .doc
        case .date_calc: return .gear
        case .unit_convert: return .gear
        case .make_qrcode: return .search
        case .ocr_image: return .search
        case .ask_user: return .sparkle
        }
    }

    private func toolBinding(_ t: ToolID) -> Binding<Bool> {
        Binding(
            get: { app.settings.enabledTools.contains(t.rawValue) },
            set: { on in
                if on {
                    if !app.settings.enabledTools.contains(t.rawValue) {
                        app.settings.enabledTools.append(t.rawValue)
                    }
                } else {
                    app.settings.enabledTools.removeAll { $0 == t.rawValue }
                }
                app.save()
            })
    }

    private func wipeSessions() {
        try? ctx.delete(model: ChatSession.self)
        try? ctx.save()
        app.runtime.reset(for: UUID())
        note = "会话已清空"
    }

    private func wipeFiles() {
        for u in app.store.allURLs() { try? FileManager.default.removeItem(at: u) }
        note = "工作区已清空"
    }
}

struct PromptEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            TextEditor(text: $app.settings.systemPrompt)
                .font(Hand.body(15))
                .foregroundStyle(Ink.line)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Ink.paper)
                .navigationTitle("系统提示词")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Ink.paper, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("恢复默认") { app.settings.systemPrompt = AppSettings.defaultSystemPrompt }
                            .font(Hand.body(15))
                            .foregroundStyle(Ink.gray)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { app.save(); dismiss() }
                            .font(Hand.body(15).weight(.semibold))
                            .foregroundStyle(Ink.line)
                    }
                }
        }
    }
}
