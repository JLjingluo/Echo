import SwiftUI
import PhotosUI

struct InputBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var appContext
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
    @State private var chips: [Suggestion] = []
    @State private var showOptions = false
    @FocusState private var focused: Bool

    private var busy: Bool { app.runtime.isBusy }
    private var hasInput: Bool { !text.trimmed.isEmpty || !images.isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            if app.voice.needsSettings { permissionBar }
            if let q = app.runtime.pendingQuestion { questionCard(q) }
            if app.runtime.needsApproval { approvalCard }

            if text.trimmed.isEmpty && images.isEmpty && !focused {
                chipRow
            }

            capsule
        }
        .padding(.horizontal, Gutter.edge)
        .onChange(of: app.voice.transcript) { _, new in
            if app.voice.listening { text = new }
        }
        .photosPicker(isPresented: $showOptions, selection: $items, maxSelectionCount: 4,
                      matching: .images)
        .onChange(of: items) { _, new in
            Task { await load(new) }
        }
        .onAppear { if chips.isEmpty { chips = EchoWheel.picks(4) } }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(Array(chips.enumerated()), id: \.offset) { i, c in
                    Button {
                        text = c.text
                        focused = true
                    } label: {
                        HStack(spacing: 6) {
                            HandIcon(glyph: glyph(c.icon), size: 15, color: Ink.gray,
                                     seed: UInt64(200 + i))
                            Text(c.text)
                                .font(Hand.pencil(17))
                                .foregroundStyle(Ink.gray)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .sketch(seed: UInt64(300 + i * 13), capsule: true, color: Ink.faint,
                                width: 1.3)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, Gutter.edge)
        }
        .frame(height: 34)
    }

    private func glyph(_ sf: String) -> HandGlyph {
        switch sf {
        case "qrcode", "qrcode.viewfinder": return .search
        case "mic": return .mic
        case "curlybraces.squiggle", "chevron.left.forwardslash.chevron.right", "function": return .doc
        case "globe", "link": return .search
        case "sparkles": return .sparkle
        default: return .doc
        }
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            Button { showOptions = true } label: {
                HandIcon(glyph: .plus, size: 20, color: Ink.line, seed: 411)
                    .frame(width: 34, height: 34)
                    .overlay {
                        SketchCircle(seed: 412, open: false)
                            .stroke(Ink.line, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(editingText == nil ? "描述任务…" : "改完点发送，从这里重来")
                        .font(Hand.pencil(19))
                        .foregroundStyle(Ink.faint)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text, axis: .vertical)
                    .focused($focused)
                    .font(Hand.body(16))
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit(send)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !images.isEmpty {
                thumbs
            }

            Button(action: toggleVoice) {
                HandIcon(glyph: .mic, size: 20,
                         color: isRecording ? Ink.accent : Ink.faint, seed: 415)
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            sendButton
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 50)
        .background(Ink.paper)
        .sketch(seed: 420, capsule: true,
                color: isRecording ? Ink.accent : Ink.line,
                width: isRecording ? 2.2 : Gutter.stroke,
                double: hasInput,
                gap: hasInput ? nil : 7)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private var thumbs: some View {
        HStack(spacing: 5) {
            ForEach(Array(images.enumerated()), id: \.offset) { idx, d in
                if let img = UIImage(data: d) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            Button { images.remove(at: idx) } label: {
                                HandIcon(glyph: .close, size: 11, color: Ink.line, seed: 430)
                                    .background(Ink.paper, in: Circle())
                            }
                            .offset(x: 5, y: -5)
                        }
                }
            }
        }
    }

    private var sendButton: some View {
        Button(action: { busy ? stop() : send() }) {
            ZStack {
                SketchCircle(seed: busy ? 441 : 440, open: !hasInput && !busy)
                    .stroke(hasInput || busy ? Ink.line : Ink.faint,
                            style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                HandIcon(glyph: busy ? .stop : .send, size: 20,
                         color: hasInput || busy ? Ink.line : Ink.faint, seed: 442)
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy ? false : !hasInput)
        .animation(.easeOut(duration: 0.15), value: hasInput)
        .accessibilityLabel(busy ? "停止" : "发送")
    }

    private var permissionBar: some View {
        Button(action: { app.voice.openSettings() }) {
            HStack(spacing: 8) {
                HandIcon(glyph: .sparkle, size: 15, color: Ink.danger, seed: 450)
                Text("\(app.voice.hint.isEmpty ? "权限没开" : app.voice.hint) · 去系统设置里打开")
                    .font(Hand.body(13))
                Spacer()
            }
            .foregroundStyle(Ink.danger)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .sketch(seed: 451, corner: 10, color: Ink.danger, gap: 3)
        }
        .buttonStyle(.plain)
    }

    private func questionCard(_ q: AgentRuntime.AskUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HandIcon(glyph: .sparkle, size: 15, color: Ink.accent, seed: 460)
                Text("Echo 要问你")
                    .font(Hand.pencil(17))
                    .foregroundStyle(Ink.gray)
                Spacer()
            }
            Text(q.question.isEmpty ? "需要你补一个信息。" : q.question)
                .font(Hand.display(20))
                .foregroundStyle(Ink.line)
                .fixedSize(horizontal: false, vertical: true)
            if !q.options.isEmpty {
                FlowLayout(spacing: 9) {
                    ForEach(q.options, id: \.self) { o in
                        Button { app.runtime.answer(o) } label: {
                            Text(o)
                                .font(Hand.body(15))
                                .padding(.horizontal, 13)
                                .frame(height: 34)
                                .sketch(seed: 465, capsule: true, double: true)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("或者自己打字回答", text: $freeAnswer)
                    .font(Hand.body(15))
                    .onSubmit(submitAnswer)
                    .sketch(seed: 468, capsule: true, color: Ink.faint, width: 1.3)
                    .padding(.horizontal, 10)
                Button(action: submitAnswer) {
                    HandIcon(glyph: .send, size: 17, color: Ink.line, seed: 470)
                        .frame(width: 34, height: 34)
                        .overlay(SketchCircle(seed: 471).stroke(Ink.line, lineWidth: 1.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.paper)
        .sketch(seed: 472, corner: 16, double: true, gap: 2)
    }

    private func submitAnswer() {
        app.runtime.answer(freeAnswer)
        freeAnswer = ""
    }

    private var approvalCard: some View {
        HStack(spacing: 10) {
            HandIcon(glyph: .check, size: 16, color: Ink.accent, seed: 480)
            Text("计划已生成，共 \(app.runtime.pendingSteps.count) 步")
                .font(Hand.body(14))
                .foregroundStyle(Ink.gray)
                .lineLimit(1)
            Spacer()
            Button("取消") { app.runtime.rejectApproval() }
                .font(Hand.body(14))
                .foregroundStyle(Ink.gray)
            Button(action: approve) {
                Text("执行")
                    .font(Hand.body(14).weight(.semibold))
                    .foregroundStyle(Ink.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .sketch(seed: 481, capsule: true, color: Ink.accent, double: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .sketch(seed: 482, corner: 12, color: Ink.gray, gap: 5)
    }

    private func approve() {
        let (hist, _) = History.build(from: session, limit: app.historyLimit)
        app.runtime.approveExecution(settings: app.settings, key: app.apiKey,
                                     session: session, context: appContext, history: hist)
    }

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
        onSend(goal, images)
        images = []
        focused = false
        editingText = nil
        chips = EchoWheel.picks(4)
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
