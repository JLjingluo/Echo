import SwiftUI
import PhotosUI

struct InputBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    let session: ChatSession
    var onOpenSettings: () -> Void

    @State private var images: [Data] = []
    @State private var picking = false
    @State private var items: [PhotosPickerItem] = []
    @State private var showOptions = false
    @State private var showModel = false
    @State private var importing = false
    @FocusState private var focused: Bool

    private var busy: Bool { app.runtime.isBusy }
    private var approval: Bool { app.runtime.needsApproval }
    private var expanded: Bool { text.contains("\n") || text.count > 72 }
    private var canSend: Bool { !text.trimmed.isEmpty || !images.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            if approval { approvalCard }
            if !images.isEmpty { tray }
            metaRow
            capsule
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.horizontal, expanded ? EchoM.expandedHInset : EchoM.collapsedHInset)
        .animation(.smooth(duration: 0.24), value: expanded)
        .photosPicker(isPresented: $picking, selection: $items, maxSelectionCount: 4,
                      matching: .images)
        .onChange(of: items) { _, new in
            Task { await load(new) }
        }
        .onChange(of: app.voice.transcript) { _, new in
            if app.voice.listening { text = new }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            if case let .ok(urls) = result { importFiles(urls) }
        }
        .sheet(isPresented: $showOptions) {
            ComposerOptionsSheet(onPhotos: { picking = true },
                                 onFiles: { importing = true },
                                 onVoice: { toggleVoice() },
                                 onPaste: { text += Notifier.paste() })
        }
        .sheet(isPresented: $showModel) { ModelPickerSheet() }
    }

    private func toggleVoice() {
        if app.voice.listening { app.voice.stop() }
        else { app.voice.start(language: app.settings.voiceLanguage) }
    }

    private func importFiles(_ urls: [URL]) {
        var out = images
        for u in urls.prefix(4) {
            let stop = u.startAccessingSecurityScopedResource()
            if let img = UIImage(contentsOfFile: u.path) { out.append(ImageOps.jpegDownscale(img)) }
            if stop { u.stopAccessingSecurityScopedResource() }
        }
        images = Array(out.suffix(4))
    }

    private var capsule: some View {
        HStack(alignment: .bottom, spacing: EchoM.collapsedTextGap) {
            Button { showOptions = true } label: {
                EchoIcon("plus", size: 24)
                    .foregroundStyle(.primary)
                    .frame(width: EchoM.touch, height: EchoM.touch)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("附件与对话选项")

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(approval ? "先确认上面的计划…" : "描述任务…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .padding(.vertical, 11)
                }
                TextField("", text: $text, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...8)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

            sendButton
        }
        .padding(.horizontal, EchoM.collapsedInset)
        .padding(.vertical, EchoM.collapsedInset)
        .glass(.rect(expanded ? EchoM.expandedRadius : EchoM.collapsedRadius), interactive: true)
    }

    private var sendButton: some View {
        let enabled = busy ? true : (canSend && app.canSend)
        return Button {
            if busy { app.runtime.cancel() } else { send() }
        } label: {
            EchoIcon(busy ? "stop.fill" : "arrow.up", size: busy ? 13 : 18,
                     weight: busy ? .regular : .semibold)
                .foregroundStyle(EchoTheme.controlForeground(scheme))
                .frame(width: EchoM.sendDiameter, height: EchoM.sendDiameter)
                .background(
                    Circle().fill(EchoTheme.controlFill(scheme).opacity(enabled ? 1 : 0.42))
                )
                .frame(width: EchoM.touch, height: EchoM.touch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy ? false : !canSend)
        .accessibilityLabel(busy ? "停止生成" : "发送消息")
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Button { showModel = true } label: {
                HStack(spacing: 6) {
                    EchoIcon("sparkles", size: 14).foregroundStyle(.secondary)
                    Text(app.settings.model.isEmpty ? "选择模型" : app.settings.model)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    EchoIcon("chevron.down", size: 12).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if app.voice.listening {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("聆听中").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
    }

    private var tray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { idx, d in
                    if let img = UIImage(data: d) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { images.remove(at: idx) } label: {
                                    EchoIcon("xmark.circle.fill", size: 19)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.7))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 9, y: -9)
                            }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var approvalCard: some View {
        HStack(spacing: 10) {
            EchoIcon("checkmark.shield", size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("计划已生成").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("共 \(app.runtime.pendingSteps.count) 步，确认后开始执行")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            EchoGlassButton("执行", style: .prominent, maxWidth: nil) { approve() }
                .font(.subheadline)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.rect(24))
    }

    private func approve() {
        let (hist, _) = History.build(from: session, limit: app.historyLimit)
        app.runtime.approveExecution(settings: app.settings, key: app.apiKey,
                                     session: session, context: context, history: hist)
    }

    private func load(_ new: [PhotosPickerItem]) async {
        guard !new.isEmpty else { return }
        var out = images
        for it in new {
            guard let d = try? await it.loadTransferable(type: Data.self),
                  let img = UIImage(data: d) else { continue }
            out.append(ImageOps.jpegDownscale(img))
        }
        images = Array(out.suffix(4))
        items = []
    }

    private func send() {
        let goal = text.trimmed
        guard !busy else { return }
        guard !goal.isEmpty || !images.isEmpty else { return }
        guard app.canSend else { onOpenSettings(); return }
        let (hist, trimmed) = History.build(from: session, limit: app.historyLimit)
        var msgs = hist
        if trimmed { msgs.insert(.plan("（更早的对话内容已省略，只保留最近若干轮）"), at: 0) }
        let final = goal.isEmpty ? "看一下这张图，说说里面有什么，需要处理就处理。" : goal
        app.runtime.start(goal: final, images: images, history: msgs, settings: app.settings,
                          key: app.apiKey, session: session, context: context)
        if trimmed { app.runtime.addNote("上下文已压缩") }
        text = ""
        images = []
        atBottomNow()
        if app.voice.listening { app.voice.stop() }
    }

    private func atBottomNow() {
        focused = false
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
