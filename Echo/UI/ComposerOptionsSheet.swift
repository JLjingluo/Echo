import SwiftUI

struct ComposerOptionsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var onPhotos: () -> Void = {}
    var onFiles: () -> Void = {}
    var onVoice: () -> Void = {}
    var onPaste: () -> Void = {}

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 12) {
                        tile("照片", icon: "photo.on.rectangle", action: onPhotos)
                        tile("文件", icon: "doc", action: onFiles)
                    }
                    .frame(maxWidth: .infinity)

                    EchoSurface {
                        VStack(spacing: 0) {
                            toggleRow("语音输入", icon: app.voice.listening ? "stop.circle.fill" : "mic",
                                      value: nil, action: onVoice)
                            Divider().padding(.leading, 52)
                            row("粘贴板", icon: "doc.on.clipboard", value: nil, action: onPaste)
                            Divider().padding(.leading, 52)
                            Menu {
                                Button("自动") { setMode("auto") }
                                Button("强制开") { setMode("on") }
                                Button("强制关") { setMode("off") }
                            } label: {
                                HStack(spacing: 14) {
                                    EchoIcon("brain.head.profile", size: 20).frame(width: 23)
                                    Text("深度思考").font(.body)
                                    Spacer(minLength: 8)
                                    Text(modeLabel).font(.subheadline).foregroundStyle(.secondary)
                                    EchoIcon("chevron.right", size: 13).foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Text(app.settings.thinkingHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            Divider().padding(.leading, 52)
                            toggle("计划自动执行", icon: "play.circle", isOn: $app.settings.autoApprove)
                            Divider().padding(.leading, 52)
                            toggle("流式输出", icon: "text.append", isOn: $app.settings.stream)
                        }
                    }

                    EchoSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("工具")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                                GridItem(.flexible(), spacing: 8)],
                                      spacing: 8) {
                                ForEach(ToolID.allCases, id: \.rawValue) { t in
                                    Toggle(isOn: toolBinding(t)) {
                                        HStack(spacing: 6) {
                                            EchoIcon(t.icon, size: 14)
                                            Text(t.label).font(.footnote.weight(.medium))
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .toggleStyle(.button)
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(16)
                    }

                    EchoSurface {
                        VStack(spacing: 0) {
                            ForEach(Array(Array(EchoAppearance.allCases).enumerated()), id: \.offset) { i, a in
                                if i > 0 { Divider().padding(.leading, 52) }
                                Button {
                                    app.appearance = a
                                    app.save()
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            EchoIcon("checkmark", size: 16, weight: .semibold)
                                                .opacity(app.appearance == a ? 1 : 0)
                                        }
                                        .frame(width: 20, height: 20)
                                        Text(a.label).font(.body.weight(.medium))
                                        Spacer()
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !NoToolMemory.all.isEmpty {
                        EchoSurface {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("被接口拒绝过工具调用的模型：\(NoToolMemory.all.joined(separator: ", "))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("清除这个记忆") {
                                    NoToolMemory.clear()
                                }
                                .font(.footnote.weight(.medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        }
                    }
                }
                .padding(20)
            }
            .buttonStyle(.plain)
            .navigationTitle("对话选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func tile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                EchoIcon(icon, size: 27).foregroundStyle(.primary)
                Text(title).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background { EchoSurface { Color.clear } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, icon: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                EchoIcon(icon, size: 20).frame(width: 23)
                Text(title).font(.body)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, icon: String, value: String?, action: @escaping () -> Void) -> some View {
        row(title, icon: icon, value: value, action: action)
    }

    private func toggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 14) {
                EchoIcon(icon, size: 20).frame(width: 23)
                Text(title).font(.body)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modeLabel: String {
        switch app.settings.thinkingMode {
        case "on": return "强制开"
        case "off": return "强制关"
        default: return "自动"
        }
    }

    private func setMode(_ v: String) {
        app.settings.thinkingMode = v
        app.save()
        Notifier.shared.tap()
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
                NoToolMemory.clear()
                app.save()
            })
    }
}
