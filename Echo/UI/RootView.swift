import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @State private var current: ChatSession?
    @State private var progress: CGFloat = 0
    @State private var open = false

    private let fraction: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width * fraction, 1)
            ZStack(alignment: .leading) {
                Ink.paper.ignoresSafeArea()

                SidebarView(current: $current, progress: $progress, open: $open,
                            sessions: sessions, reveal: w)
                    .frame(width: w)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .background(Ink.paper)
                    .scaleEffect(0.96 + 0.04 * progress, anchor: .leading)
                    .allowsHitTesting(progress > 0.001)

                detail(reveal: w)

                if progress > 0.001 {
                    Hatch(spacing: 9, inset: 0)
                        .stroke(Ink.line.opacity(0.07 * Double(progress)), lineWidth: 1)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if progress <= 0.001 {
                    HStack {
                        Color.clear
                            .frame(width: 44)
                            .contentShape(Rectangle())
                            .gesture(edgeDrag(w))
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: ensure)
        .onChange(of: sessions.count) { _, _ in ensure() }
    }

    @ViewBuilder
    private func detail(reveal: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: progress > 0.001 ? 26 : 0, style: .continuous)
        Group {
            if let s = current {
                ChatView(session: s,
                         onMenu: { settle(true) },
                         onNew: { newSession(); settle(false) })
                    .id(s.id)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper)
        .clipShape(shape)
        .overlay {
            if progress > 0.001 {
                shape.stroke(Ink.line.opacity(0.5 * progress), lineWidth: 1.6)
            }
        }
        .offset(x: reveal * progress)
        .overlay {
            if progress > 0.001 {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { settle(false) }
            }
        }
    }

    private func edgeDrag(_ reveal: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                progress = min(max(v.translation.width / reveal, 0), 1)
            }
            .onEnded { v in
                let projected = (v.translation.width + v.velocity.width * 0.2) / reveal
                settle(projected >= 0.5, velocity: v.velocity.width / reveal)
            }
    }

    func settle(_ target: Bool, velocity: CGFloat = 0) {
        let remaining = max(target ? 1 - progress : progress, 0.02)
        let v = min(max(velocity / remaining, -8), 8)
        if UIAccessibility.isReduceMotionEnabled {
            progress = target ? 1 : 0
            open = target
            return
        }
        withAnimation(.interpolatingSpring(stiffness: 341, damping: 33, initialVelocity: v)) {
            progress = target ? 1 : 0
        }
        if open != target {
            open = target
            Notifier.shared.tap()
        }
    }

    private func ensure() {
        if let c = current, sessions.contains(where: { $0.id == c.id }) { return }
        if let first = sessions.first {
            current = first
        } else {
            newSession()
        }
    }

    private func newSession() {
        let s = ChatSession()
        context.insert(s)
        try? context.save()
        current = s
    }
}

struct ConversationGroup: Hashable {
    let date: Date
    var items: [ChatSession]
}

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Binding var current: ChatSession?
    @Binding var progress: CGFloat
    @Binding var open: Bool
    let sessions: [ChatSession]
    let reveal: CGFloat
    @State private var showSettings = false
    @State private var renaming: ChatSession?
    @State private var draft = ""

    private var groups: [ConversationGroup] {
        let dict = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.updatedAt) }
        return dict.map { ConversationGroup(date: $0.key, items: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Echo")
                        .font(Hand.display(26))
                        .foregroundStyle(Ink.line)
                    Spacer()
                    BrandFace(size: 34, seed: 1234)
                }
                Button(action: newConversation) {
                    HStack(spacing: 8) {
                        HandIcon(glyph: .plus, size: 17, color: Ink.line, seed: 601)
                        Text("新对话")
                            .font(Hand.body(16).weight(.semibold))
                            .foregroundStyle(Ink.line)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .sketch(seed: 602, capsule: true, double: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Gutter.edge)
            .padding(.top, Device.topInset + 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.date) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.date.daysAgoString())
                                .font(Hand.pencil(18))
                                .foregroundStyle(Ink.faint)
                                .padding(.bottom, 2)
                                .contextMenu {
                                    Button(role: .destructive, action: { deleteDay(g) }) {
                                        Label("删除当天全部会话", systemImage: "trash")
                                    }
                                }
                            ForEach(g.items) { s in row(s) }
                        }
                    }
                    if sessions.isEmpty {
                        Text("还没有会话")
                            .font(Hand.body(14))
                            .foregroundStyle(Ink.faint)
                    }
                }
                .padding(.horizontal, Gutter.edge)
                .padding(.top, 18)
                .padding(.bottom, Device.bottomInset + 96)
            }
            .contentShape(Rectangle())
            .gesture(dismissDrag)

            HStack(spacing: 10) {
                BrandFace(size: 30, seed: 777)
                Text("本机")
                    .font(Hand.body(15))
                    .foregroundStyle(Ink.gray)
                Spacer()
                Button { showSettings = true } label: {
                    HandIcon(glyph: .gear, size: 20, color: Ink.line, seed: 611)
                        .frame(width: 44, height: 44)
                        .overlay(SketchCircle(seed: 612).stroke(Ink.line, lineWidth: 1.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
            }
            .padding(.horizontal, Gutter.edge)
            .padding(.bottom, Device.bottomInset + 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            VStack(spacing: 3) {
                Rectangle().fill(Ink.line.opacity(0.85)).frame(width: 1.6)
                Rectangle().fill(Ink.line.opacity(0.3)).frame(width: 1)
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("重命名会话", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("会话标题", text: $draft)
            Button("取消", role: .cancel) { renaming = nil }
            Button("存储") {
                if let s = renaming {
                    let t = draft.trimmed
                    if !t.isEmpty { s.title = t.clamped(24) }
                    try? context.save()
                }
                renaming = nil
            }
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                progress = min(max(1 + v.translation.width / reveal, 0), 1)
            }
            .onEnded { v in
                let projected = 1 + (v.translation.width + v.velocity.width * 0.2) / reveal
                withAnimation(.interpolatingSpring(stiffness: 341, damping: 33)) {
                    progress = projected >= 0.5 ? 1 : 0
                }
                open = projected >= 0.5
            }
    }

    private func row(_ s: ChatSession) -> some View {
        let active = current?.id == s.id
        return Button {
            app.runtime.persistIfNeeded(session: s, context: context)
            current = s
            withAnimation(.interpolatingSpring(stiffness: 341, damping: 33)) { progress = 0 }
            open = false
        } label: {
            HStack(spacing: 10) {
                HandIcon(glyph: .doc, size: 17, color: active ? Ink.accent : Ink.gray,
                         seed: 620)
                Text(s.title.isEmpty ? "新会话" : s.title)
                    .font(Hand.body(16).weight(active ? .semibold : .regular))
                    .foregroundStyle(active ? Ink.line : Ink.gray)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if app.runtime.sessionId == s.id && app.runtime.needsApproval {
                    Circle().fill(Ink.accent).frame(width: 7, height: 7)
                } else if app.runtime.sessionId == s.id && app.runtime.isBusy {
                    RedrawSpinner(size: 15)
                } else if active {
                    Circle().fill(Ink.line).frame(width: 5, height: 5)
                }
            }
            .frame(height: 50)
            .padding(.horizontal, active ? 8 : 0)
            .overlay {
                if active {
                    SketchRect(seed: 621, corner: 14, wobble: 1.6)
                        .stroke(Ink.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .offset(x: -6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("重命名", systemImage: "pencil") {
                draft = s.title
                renaming = s
            }
            Button(role: .destructive, action: { delete(s) }) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func delete(_ s: ChatSession) {
        context.delete(s)
        try? context.save()
        if current?.id == s.id { current = nil }
    }

    private func deleteDay(_ g: ConversationGroup) {
        for s in g.items { delete(s) }
    }

    private func newConversation() {
        let s = ChatSession()
        context.insert(s)
        try? context.save()
        current = s
        withAnimation(.interpolatingSpring(stiffness: 341, damping: 33)) { progress = 0 }
        open = false
    }
}

struct RedrawSpinner: View {
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0.35 : (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
            Canvas { ctx, sz in
                let box = CGRect(origin: .zero, size: sz).insetBy(dx: 1.5, dy: 1.5)
                let base = Path(ellipseIn: box)
                let arc = base.trimmedPath(from: 0, to: 0.28 + 0.5 * phase)
                ctx.stroke(arc, with: .color(Ink.line.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
            .frame(width: size, height: size)
        }
        .onAppear { _ = turn }
        .accessibilityHidden(true)
    }
}
