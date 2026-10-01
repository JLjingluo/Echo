import SwiftUI
import PhotosUI

struct InputBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Binding var text: String
    let session: ChatSession
    var onOpenSettings: () -> Void

    @State private var images: [Data] = []
    @State private var picking = false
    @State private var items: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    private var busy: Bool { app.runtime.isBusy }
    private var approval: Bool { app.runtime.needsApproval }

    var body: some View {
        VStack(spacing: 8) {
            if approval { approvalBar }
            if !images.isEmpty { chips }
            if focused || !text.isEmpty { metaRow }

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button("相册 / 拍照", systemImage: "photo.on.rectangle") { picking = true }
                    Button("粘贴板", systemImage: "doc.on.clipboard") {
                        text += Notifier.paste()
                    }
                    Button(app.voice.listening ? "停止语音" : "语音输入",
                           systemImage: app.voice.listening ? "stop.fill" : "mic") {
                        if app.voice.listening { app.voice.stop() }
                        else { app.voice.start(language: app.settings.voiceLanguage) }
                    }
                    if !text.isEmpty {
                        Button("清空", systemImage: "trash", role: .destructive) { text = "" }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                TextField(approval ? "先确认上面的计划…" : "描述任务…", text: $text, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(1...7)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: app.voice.transcript) { _, new in
                        if app.voice.listening { text = new }
                    }

                sendButton
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .photosPicker(isPresented: $picking, selection: $items, maxSelectionCount: 4, matching: .images)
        .onChange(of: items) { _, new in
            Task { await load(new) }
        }
    }

    private var sendButton: some View {
        Group {
            if busy {
                CircleFillButton(system: "stop.fill", filled: true) { app.runtime.cancel() }
            } else {
                CircleFillButton(system: "arrow.up", filled: !text.trimmed.isEmpty || !images.isEmpty) {
                    send()
                }
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { idx, d in
                if let img = UIImage(data: d) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                images.remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .offset(x: 5, y: -5)
                        }
                }
            }
            Spacer()
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Button(action: onOpenSettings) {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                    Text(shortModel)
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glass(.capsule, interactive: true)
            }
            .buttonStyle(.plain)
            if app.settings.modelSupportsTools {
                Button {
                    app.settings.deepThink.toggle()
                    app.save()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: app.settings.deepThink ? "brain.head.profile" : "brain")
                        Text("深度思考")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(app.settings.deepThink ? Color(hex: "D9483B") : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glass(.capsule, interactive: true)
                }
            }
            Spacer()
            if app.voice.listening {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "D9483B")).frame(width: 7, height: 7)
                    Text("聆听中").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var approvalBar: some View {
        HStack(spacing: 10) {
            Text("计划已生成，确认后开始执行")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("取消") { app.runtime.rejectApproval() }
                .font(.system(size: 13, weight: .medium))
            Button {
                let (hist, _) = History.build(from: session, limit: app.historyLimit)
                app.runtime.approveExecution(settings: app.settings, key: app.apiKey,
                                             session: session, context: context, history: hist)
            } label: {
                Text("执行")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: "F6F6F8"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var shortModel: String {
        let m = app.settings.model
        return m.count > 22 ? String(m.prefix(21)) + "…" : m
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
        if app.voice.listening { app.voice.stop() }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
