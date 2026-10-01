import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @State private var current: ChatSession?
    @State private var progress: CGFloat = 0
    @State private var open = false

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width * EchoM.drawerFraction, 1)
            ZStack(alignment: .leading) {
                Ench.background.ignoresSafeArea()

                SidebarView(current: $current, progress: $progress, open: $open,
                            sessions: sessions, reveal: w, insets: geo.safeAreaInsets)
                    .frame(width: w)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .background(Ench.background)
                    .scaleEffect(EchoM.closedScale + (1 - EchoM.closedScale) * progress,
                                 anchor: .leading)
                    .overlay {
                        Ench.background
                            .opacity(EchoM.sidebarVeil * (1 - min(max(progress, 0), 1)))
                    }
                    .allowsHitTesting(progress > 0.001)

                detail(reveal: w)

                if progress <= 0.001 {
                    HStack {
                        Color.clear
                            .frame(width: EchoM.edgeActivation)
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
        let shape = RoundedRectangle(cornerRadius: progress > 0.001 ? 30 : 0, style: .continuous)
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
        .background(Ench.background)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.2 * progress), lineWidth: 1) }
        .overlay { Color.white.opacity(EchoM.contentScrim * progress) }
        .shadow(color: .black.opacity(0.28 * progress), radius: 18, x: -3, y: 0)
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
    let insets: EdgeInsets
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
            Button(action: newConversation) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                    Text("新会话").font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(GrowingButton())
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(groups, id: \.date) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(g.date.daysAgoString())
                                    .font(.system(size: 14))
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(.systemGray))
                                Spacer()
                            }
                            .contextMenu {
                                Button(role: .destructive, action: { deleteDay(g) }) {
                                    Label("删除当天全部会话", systemImage: "trash")
                                }
                            }

                            ForEach(g.items) { s in row(s) }

                            Divider()
                        }
                    }

                    if sessions.isEmpty {
                        Text("还没有会话")
                            .font(.system(size: 14))
                            .foregroundColor(Color(.systemGray))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, insets.bottom + 40)
            }
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .gesture(dismissDrag)

            HStack(spacing: 10) {
                Text("Echo")
                    .font(.system(size: 22, weight: .thin))
                    .foregroundStyle(Ench.brandGradient)
                Spacer()
                Text(AppVersion.text)
                    .font(.system(size: 11))
                    .foregroundStyle(Ench.tertiaryText)
                    .padding(.trailing, 4)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(.label))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(GrowingButton())
                .accessibilityLabel("设置")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, max(insets.bottom, 12))
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
        Button {
            app.runtime.persistIfNeeded(session: s, context: context)
            current = s
            withAnimation(.interpolatingSpring(stiffness: 341, damping: 33)) { progress = 0 }
            open = false
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .frame(width: 6, height: 6)
                    .animation(.easeOut(duration: 0.15))
                    .transition(.opacity)
                    .showIf(current?.id == s.id)
                Text(s.title.isEmpty ? "新会话" : s.title)
                    .lineLimit(1)
                    .font(.system(size: 16))
                    .foregroundColor(Color(.label))
                    .animation(.easeOut(duration: 0.15))
                if app.runtime.sessionId == s.id && app.runtime.needsApproval {
                    StatusDot(color: .orange, pulsing: true)
                } else if app.runtime.sessionId == s.id && app.runtime.isBusy {
                    StatusDot(color: .green, pulsing: true)
                }
                Spacer()
            }
            .animation(.easeOut(duration: 0.15))
            .padding(.vertical, 4)
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
