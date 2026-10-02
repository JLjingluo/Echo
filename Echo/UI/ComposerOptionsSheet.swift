import SwiftUI

struct ComposerOptionsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var onPhotos: () -> Void = {}
    var onFiles: () -> Void = {}
    var onVoice: () -> Void = {}
    var onPaste: () -> Void = {}

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        tile("照片", glyph: .search, action: onPhotos)
                        tile("文件", glyph: .folder, action: onFiles)
                        tile(app.voice.listening ? "停止听" : "语音", glyph: .mic, action: onVoice)
                        tile("粘贴板", glyph: .doc, action: onPaste)
                    }
                    .padding(.top, 8)

                    HandSectionHeader(text: "这一轮")
                    HStack(spacing: 10) {
                        Text("深度思考").font(Hand.body(16)).foregroundStyle(Ink.line)
                        Spacer()
                        HandSegmented(options: [("自动", "auto"), ("开", "on"), ("关", "off")],
                                      selection: thinkingBinding)
                    }
                    .frame(minHeight: 50)
                    Text(app.settings.thinkingHint)
                        .font(Hand.body(12)).foregroundStyle(Ink.gray)
                    HStack(spacing: 10) {
                        Text("计划自动执行").font(Hand.body(16)).foregroundStyle(Ink.line)
                        Spacer()
                        HandToggle(isOn: $app.settings.autoApprove, seed: 901)
                    }
                    .frame(minHeight: 50)
                    HStack(spacing: 10) {
                        Text("流式输出").font(Hand.body(16)).foregroundStyle(Ink.line)
                        Spacer()
                        HandToggle(isOn: $app.settings.stream, seed: 902)
                    }
                    .frame(minHeight: 50)

                    HandSectionHeader(text: "工具")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(ToolID.allCases.enumerated()), id: \.offset) { i, t in
                            HStack(spacing: 8) {
                                Text(t.label)
                                    .font(Hand.body(14))
                                    .foregroundStyle(app.settings.enabledTools.contains(t.rawValue)
                                                     ? Ink.line : Ink.faint)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                HandToggle(isOn: toolBinding(t), seed: UInt64(910 + i))
                                    .scaleEffect(0.85)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .sketch(seed: UInt64(930 + i), corner: 12,
                                    color: app.settings.enabledTools.contains(t.rawValue)
                                        ? Ink.line : Ink.faint, width: 1.3)
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

                    if !NoToolMemory.all.isEmpty {
                        HandSectionHeader(text: "工具记忆")
                        Text("这些模型被接口拒绝过工具调用：" + NoToolMemory.all.joined(separator: ", "))
                            .font(Hand.body(13)).foregroundStyle(Ink.gray)
                        Button {
                            NoToolMemory.clear()
                            dismiss()
                        } label: {
                            Text("清除这个记忆")
                                .font(Hand.body(14).weight(.semibold))
                                .foregroundStyle(Ink.accent)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .sketch(seed: 941, capsule: true, color: Ink.accent, width: 1.4)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Gutter.edge)
            }
            .scrollIndicators(.hidden)
            .background(Ink.paper.ignoresSafeArea())
            .overlay { PaperGrain(density: 400).ignoresSafeArea() }
            .navigationTitle("对话选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Ink.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HandIcon(glyph: .close, size: 15, color: Ink.line, seed: 950)
                            .frame(width: 34, height: 34)
                            .overlay(SketchCircle(seed: 951)
                                .stroke(Ink.line, lineWidth: 1.5))
                    }
                }
            }
        }
    }

    private func tile(_ title: String, glyph: HandGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HandIcon(glyph: glyph, size: 22, color: Ink.line, seed: 960)
                Text(title).font(Hand.body(14)).foregroundStyle(Ink.line)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .sketch(seed: 961, corner: 14, double: true, gap: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thinkingBinding: Binding<String> {
        Binding(get: { app.settings.thinkingMode },
                set: { app.settings.thinkingMode = $0; app.save() })
    }

    private var appearanceBinding: Binding<String> {
        Binding(get: { app.appearance.rawValue },
                set: { app.appearance = EchoAppearance(rawValue: $0) ?? .system; app.save() })
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
