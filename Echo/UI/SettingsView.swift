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
            Form {
                Section("模型厂商") {
                    ForEach(Array(vendorPresets.enumerated()), id: \.offset) { _, v in
                        Button {
                            app.apply(v)
                            note = "已切到 \(v.name)"
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name).font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(v.baseURL.isEmpty ? "自己填 Base URL" : v.baseURL)
                                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if app.settings.vendorID == v.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Group {
                            if showKey {
                                TextField("API Key", text: $app.apiKey)
                            } else {
                                SecureField("API Key", text: $app.apiKey)
                            }
                        }
                        .font(.system(size: 15, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: app.apiKey) { _, _ in app.saveKey() }
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    if let vendor = app.vendor, !vendor.keyURL.isEmpty {
                        Link(destination: URL(string: vendor.keyURL)!) {
                            HStack { Image(systemName: "key.horizontal"); Text("去 \(vendor.name) 控制台创建 Key") }
                        }
                    }
                    if let vendor = app.vendor, !vendor.note.isEmpty {
                        Text(vendor.note).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("API Key（只存本机钥匙串）")
                } footer: {
                    Text("每个厂商的 Key 分开保存，切厂商不会丢。")
                }

                Section {
                    Button { showModel = true } label: {
                        HStack {
                            Text("厂商与模型")
                            Spacer()
                            Text(app.settings.model.isEmpty ? "未选" : app.settings.model)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .sheet(isPresented: $showModel) { ModelPickerSheet() }
                    if !NoToolMemory.all.isEmpty {
                        Button("清除「这个模型不能调工具」的记忆（\(NoToolMemory.all.count)）") {
                            NoToolMemory.clear()
                            note = "已清除，下次会重新尝试调用工具"
                        }
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text("填好 Key 后进入「厂商与模型」，点读取按钮就能选厂商官方列出的所有模型。")
                }

                Section("外观") {
                    Picker("配色", selection: $app.appearance) {
                        ForEach(EchoAppearance.allCases) { a in Text(a.label).tag(a) }
                    }
                }

                Section("生成") {
                    Toggle("流式输出", isOn: $app.settings.stream)
                    Toggle("深度思考（更慢更准）", isOn: $app.settings.deepThink)
                    VStack(alignment: .leading) {
                        Text("温度 \(app.settings.temperature, specifier: "%.2f")")
                            .font(.system(size: 13))
                        Slider(value: $app.settings.temperature, in: 0...2, step: 0.05)
                    }
                    Stepper("最长回复 \(app.settings.maxTokens) tokens",
                            value: $app.settings.maxTokens, in: 512...32000, step: 512)
                }

                Section("Agent 行为") {
                    Toggle("计划自动执行（关掉会先等你确认）", isOn: $app.settings.autoApprove)
                    Stepper("每步最多 \(app.settings.maxTurnsPerStep) 轮",
                            value: $app.settings.maxTurnsPerStep, in: 2...12)
                    Stepper("带上 \(app.settings.historyLimit) 条历史",
                            value: $app.settings.historyLimit, in: 4...80, step: 2)
                    Toggle("触感反馈", isOn: $app.settings.haptics)
                    Toggle("跑完自动弹出导出到「文件」App", isOn: $app.settings.autoExport)
                }

                Section("工具") {
                    ForEach(ToolID.allCases, id: \.rawValue) { t in
                        Toggle(isOn: toolBinding(t)) {
                            Label(t.label, systemImage: t.icon)
                                .font(.system(size: 15))
                        }
                    }
                }

                Section {
                    Button { promptEditing = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("系统提示词").font(.system(size: 15)).foregroundStyle(.primary)
                            Text(app.settings.systemPrompt)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .sheet(isPresented: $promptEditing) { PromptEditor() }
                } header: {
                    Text("人设与规则")
                }

                Section("联网搜索（可选）") {
                    TextField("自定义搜索接口", text: $app.settings.searchEndpoint)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("搜索接口 Key", text: Binding(
                        get: { EchoSecrets.searchKey },
                        set: { EchoSecrets.searchKey = $0 }))
                        .font(.system(size: 13, design: .monospaced))
                    Text("留空则用内置的公共搜索引擎，可能被限流。Key 存在钥匙串，不进设置文件。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                Section("数据") {
                    if EchoState.storeDegraded {
                        Label("数据库打不开，本次会话只存在内存里，关掉就没了。重装 App 可以恢复。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.red)
                    }
                    LabeledContent("工作区占用",
                                   value: ToolOutcome.sizeText(app.store.totalBytes()))
                    Button("清空所有会话", role: .destructive) { confirmSessions = true }
                    Button("清空工作区文件", role: .destructive) { confirmFiles = true }
                    LabeledContent("版本", value: AppVersion.text)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { app.save(); dismiss() } }
            }
            .onChange(of: app.settings) { _, _ in app.save() }
            .confirmationDialog("清空所有会话？", isPresented: $confirmSessions,
                                titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    try? ctx.delete(model: ChatSession.self)
                    try? ctx.save()
                    app.runtime.reset(for: UUID())
                    note = "会话已清空"
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有聊天记录会立刻删除，撤销不了。")
            }
            .confirmationDialog("清空工作区文件？", isPresented: $confirmFiles,
                                titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    for u in app.store.allURLs() { try? FileManager.default.removeItem(at: u) }
                    note = "工作区已清空"
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("Agent 生成的文件会从本机删除。已经导出到「文件」App 的不受影响。")
            }
            .safeAreaInset(edge: .bottom) {
                if !note.isEmpty {
                    Text(note).font(.system(size: 13))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glass(.capsule).padding(.bottom, 6)
                }
            }
        }
    }

    private func toolBinding(_ t: ToolID) -> Binding<Bool> {
        Binding(
            get: { app.settings.enabledTools.contains(t.rawValue) },
            set: { on in
                if on {
                    if !app.settings.enabledTools.contains(t.rawValue) { app.settings.enabledTools.append(t.rawValue) }
                } else {
                    app.settings.enabledTools.removeAll { $0 == t.rawValue }
                }
                app.save()
            })
    }
}

struct PromptEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            TextEditor(text: $app.settings.systemPrompt)
                .font(.system(size: 14))
                .padding(8)
                .scrollContentBackground(.hidden)
                .navigationTitle("系统提示词")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("恢复默认") { app.settings.systemPrompt = AppSettings.defaultSystemPrompt }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { app.save(); dismiss() }
                    }
                }
        }
    }
}
