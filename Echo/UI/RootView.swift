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
                EchoTheme.background(scheme).ignoresSafeArea()

                SidebarView(current: $current, progress: $progress, open: $open,
                            sessions: sessions, reveal: w, insets: geo.safeAreaInsets)
                    .frame(width: w)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .background(EchoTheme.background(scheme))
                    .scaleEffect(EchoM.closedScale + (1 - EchoM.closedScale) * progress,
                                 anchor: .leading)
                    .overlay {
                        EchoTheme.background(scheme)
                            .opacity(EchoM.sidebarVeil * (1 - min(max(progress, 0), 1)))
                    }
                    .allowsHitTesting(progress > 0.001)

                detail(insets: geo.safeAreaInsets, reveal: w)

                if progress <= 0.001 {
                    HStack {
                        Color.clear
                            .frame(width: EchoM.edgeActivation)
                            .contentShape(Rectangle())
                            .gesture(edgeDrag(w))
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(true)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: ensure)
        .onChange(of: sessions.count) { _, _ in ensure() }
    }

    @ViewBuilder
    private func detail(insets: EdgeInsets, reveal: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: progress > 0.001 ? 30 : 0, style: .continuous)
        Group {
            if let s = current {
                ChatView(session: s, onMenu: { settle(true) })
                    .id(s.id)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoTheme.background(scheme))
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

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Binding var current: ChatSession?
    @Binding var progress: CGFloat
    @Binding var open: Bool
    let sessions: [ChatSession]
    let reveal: CGFloat
    let insets: EdgeInsets
    @State private var showSettings = false
    @State private var renaming: ChatSession?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Echo")
                .font(EchoFont.wordmark(26))
                .foregroundStyle(EchoTheme.primaryText(scheme))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, insets.top)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("会话")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(sessions.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, EchoM.sectionInset)
                    .padding(.top, 20)
                    .padding(.bottom, 6)

                    ForEach(sessions) { s in row(s) }

                    if sessions.isEmpty {
                        Text("还没有会话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, EchoM.sectionInset)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    }
                }
                .padding(.horizontal, EchoM.contentInset)
                .padding(.top, 10)
                .padding(.bottom, insets.bottom + EchoM.footerClear)
            }
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .gesture(dismissDrag)
            .overlay(alignment: .bottom) { footer }
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
        let active = current?.id == s.id
        return Button {
            app.runtime.persistIfNeeded(session: s, context: context)
            current = s
            withAnimation(.interpolatingSpring(stiffness: 341, damping: 33)) {
                progress = 0
            }
            open = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(s.title.isEmpty ? "新会话" : s.title)
                        .font(.body)
                        .foregroundStyle(EchoTheme.primaryText(scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    indicator(s)
                }
                Text(s.previewText.trimmed.isEmpty ? "还没有内容" : s.previewText.trimmed)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: EchoM.rowHeight)
            .background {
                if active {
                    Rectangle()
                        .fill(EchoTheme.selectionFill(scheme))
                        .padding(.leading, -(EchoM.contentInset + insets.leading))
                        .padding(.trailing, -(EchoM.contentInset + insets.trailing))
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
            Button("删除", systemImage: "trash", role: .destructive) {
                context.delete(s)
                try? context.save()
                if current?.id == s.id { current = nil }
            }
        }
    }

    @ViewBuilder
    private func indicator(_ s: ChatSession) -> some View {
        if app.runtime.sessionId == s.id && app.runtime.needsApproval {
            Text("等待批准")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.mint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.mint.opacity(0.16), in: Capsule())
                .fixedSize()
        } else if app.runtime.sessionId == s.id && app.runtime.isBusy {
            ProgressView()
                .controlSize(.mini)
                .tint(.primary)
                .frame(width: 14, height: 14)
        } else if app.runtime.sessionId == s.id && app.runtime.phase == .failed {
            EchoIcon("exclamationmark.circle", size: 14).foregroundStyle(.red)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            EchoGlassButton("新会话", systemImage: "square.and.pencil", style: .prominent,
                            maxWidth: nil) {
                let s = ChatSession()
                context.insert(s)
                try? context.save()
                current = s
                withAnimation(.interpolatingSpring(stiffness: 341, damping: 33)) {
                    progress = 0
                }
                open = false
            }
            .font(.body.weight(.semibold))

            Spacer(minLength: 12)

            Button { showSettings = true } label: {
                EchoIcon("gearshape", size: 19)
                    .foregroundStyle(EchoTheme.primaryText(scheme))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glass(.circle)
            .accessibilityLabel("设置")
        }
        .padding(.leading, EchoM.contentInset + 4)
        .padding(.trailing, EchoM.contentInset + 4)
        .frame(height: EchoM.touch + 8)
        .padding(.bottom, max(insets.bottom, 12))
    }
}
