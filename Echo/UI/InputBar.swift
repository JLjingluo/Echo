import SwiftUI
import PhotosUI

struct SimpleFloatingButton: View {
    var systemImage: String
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: systemImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(.label))
                .frame(height: 18)
        }
        .buttonStyle(GrowingButton())
        .contentShape(Rectangle())
    }
}

struct InputBar: View {
    @Environment(AppState.self) private var app
    @Binding var text: String
    @Binding var editingText: String?
    let session: ChatSession
    var onSend: (String, [Data]) -> Void
    var onStop: () -> Void
    var onOpenSettings: () -> Void

    @State private var images: [Data] = []
    @State private var items: [PhotosPickerItem] = []
    @State private var isRecording = false
    @State private var freeAnswer = ""
    @FocusState private var focused: Bool

    private var busy: Bool { app.runtime.isBusy }

    var body: some View {
        VStack(spacing: 8) {
            if app.voice.needsSettings {
                Button(action: { app.voice.openSettings() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                        Text("\(app.voice.hint.isEmpty ? "权限没开" : app.voice.hint) · 去开启")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundStyle(DiffTheme.delText)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DiffTheme.delFill))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(DiffTheme.delText.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(GrowingButton())
            }

            if let q = app.runtime.pendingQuestion { questionCard(q) }

            if app.runtime.needsApproval { approvalCard }

            HStack(spacing: 10) {
                PhotosPicker(selection: $items, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 19)
                        .foregroundStyle(.foreground)
                }
                .onChange(of: items) { _, new in
                    Task { await load(new) }
                }

                HStack(spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, d in
                        if let img = UIImage(data: d) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topTrailing) {
                                    Button { images.remove(at: idx) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                        }
                    }

                    TextField(editingText == nil ? "消息" : "改完点发送，从这里重来",
                              text: $text, axis: .vertical)
                        .focused($focused)
                        .frame(minHeight: 40)
                        .font(.system(size: 14))
                        .submitLabel(.send)
                        .onSubmit(send)

                    Button(action: toggleVoice) {
                        if isRecording {
                            ZStack {
                                Color(.systemBlue)
                                Image(systemName: "square.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .frame(width: 8)
                            }
                            .clipShape(Circle())
                            .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "waveform")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 20)
                                .foregroundStyle(Color(.systemGray))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            isRecording ? Color(.systemBlue) : Color(.systemGray2),
                            style: StrokeStyle(lineWidth: isRecording ? 2 : 0.5)
                        )
                )

                if busy {
                    SimpleFloatingButton(systemImage: "square.fill", onClick: stop)
                        .frame(width: 12)
                } else {
                    SimpleFloatingButton(systemImage: "paperplane.fill", onClick: send)
                        .frame(width: 18)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .padding(.horizontal)
        .onChange(of: app.voice.transcript) { _, new in
            if app.voice.listening { text = new }
        }
    }

    private func questionCard(_ q: AgentRuntime.AskUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill").font(.system(size: 14))
                Text("Echo 要问你")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ench.secondaryText)
                Spacer()
            }
            Text(q.question.isEmpty ? "需要你补一个信息。" : q.question)
                .font(.system(size: 16))
                .fixedSize(horizontal: false, vertical: true)
            if !q.options.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(q.options, id: \.self) { o in
                        Button { app.runtime.answer(o) } label: {
                            Text(o)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 13)
                                .frame(minHeight: 34)
                                .background(Capsule().fill(Ench.text.opacity(0.10)))
                                .overlay(Capsule().stroke(Ench.border, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(GrowingButton())
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("或者自己打字回答", text: $freeAnswer)
                    .font(.system(size: 14))
                    .onSubmit { submitAnswer() }
                Button(action: submitAnswer) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ench.background)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Ench.text))
                }
                .buttonStyle(GrowingButton())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ench.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Ench.cardStroke, lineWidth: 1))
    }

    private func submitAnswer() {
        app.runtime.answer(freeAnswer)
        freeAnswer = ""
    }

    private var approvalCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundStyle(Ench.secondaryText)
            Text("计划已生成，共 \(app.runtime.pendingSteps.count) 步")
                .font(.system(size: Ench.body))
                .lineLimit(1)
            Spacer()
            Button("取消") { app.runtime.rejectApproval() }
                .font(.system(size: Ench.body))
                .foregroundStyle(Ench.secondaryText)
            Button(action: approve) {
                Text("执行")
                    .font(.system(size: Ench.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(.label)))
            }
            .buttonStyle(GrowingButton())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ench.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Ench.cardStroke, lineWidth: 1))
    }

    private func approve() {
        let (hist, _) = History.build(from: session, limit: app.historyLimit)
        app.runtime.approveExecution(settings: app.settings, key: app.apiKey,
                                     session: session, context: appContext, history: hist)
    }

    @Environment(\.modelContext) private var appContext

    private func toggleVoice() {
        if app.voice.listening {
            app.voice.stop()
            isRecording = false
        } else {
            app.voice.start(language: app.settings.voiceLanguage)
            isRecording = true
        }
    }

    private func stop() {
        onStop()
        isRecording = false
        if app.voice.listening { app.voice.stop() }
    }

    private func send() {
        guard !busy else { return }
        let goal = text.trimmed
        guard !goal.isEmpty || !images.isEmpty else { return }
        withAnimation {
            onSend(goal, images)
            images = []
            focused = false
            editingText = nil
        }
        if app.voice.listening { app.voice.stop(); isRecording = false }
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
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
