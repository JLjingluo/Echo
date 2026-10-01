import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @State private var current: ChatSession?
    @State private var drawer = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color(.systemBackground).ignoresSafeArea()

            Group {
                if let s = current {
                    ChatView(session: s, onMenu: { withAnimation(.snappy) { drawer = true } })
                        .id(s.id)
                } else {
                    ProgressView().controlSize(.large)
                }
            }

            if drawer {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { drawer = false } }
                    .transition(.opacity)

                SidebarView(current: $current, drawer: $drawer, sessions: sessions)
                    .frame(width: min(340, UIScreen.main.bounds.width * 0.86))
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 26, y: 6)
                    .transition(.move(edge: .leading))
            }
        }
        .onAppear(perform: ensure)
        .onChange(of: sessions.count) { _, _ in ensure() }
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
    @Binding var current: ChatSession?
    @Binding var drawer: Bool
    let sessions: [ChatSession]
    @State private var showSettings = false
    @State private var query = ""

    var filtered: [ChatSession] {
        query.trimmed.isEmpty ? sessions
            : sessions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Echo")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .italic()
                .padding(.top, 60)
                .padding(.horizontal, 22)

            HStack {
                Text("会话").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(sessions.count)").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(filtered) { s in
                        row(s)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            HStack(spacing: 12) {
                Button {
                    let s = ChatSession()
                    context.insert(s)
                    try? context.save()
                    current = s
                    withAnimation(.snappy) { drawer = false }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text("新会话").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func row(_ s: ChatSession) -> some View {
        let active = current?.id == s.id
        return Button {
            app.runtime.persistIfNeeded(session: s, context: context)
            current = s
            withAnimation(.snappy) { drawer = false }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(s.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    if app.runtime.sessionId == s.id && app.runtime.isBusy {
                        Circle().fill(Color(hex: "2FA46B")).frame(width: 7, height: 7)
                    }
                }
                Text(s.previewText.trimmed.isEmpty ? "还没有内容" : s.previewText.trimmed)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.primary.opacity(0.07) : .clear,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除", role: .destructive) {
                context.delete(s)
                try? context.save()
                if current?.id == s.id { current = nil }
            }
        }
    }
}
