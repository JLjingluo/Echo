import SwiftUI
import SwiftData

@main
struct EchoApp: App {
    @State private var app = AppState()
    @State private var showOnboard = false
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration("EchoStore", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: ChatSession.self, ChatMessage.self, MsgBlock.self,
                                      configurations: [config])
        } catch {
            wipeStore()
            do {
                return try ModelContainer(for: ChatSession.self, ChatMessage.self, MsgBlock.self,
                                          configurations: [config])
            } catch {
                fatalError("数据库初始化失败：\(error.localizedDescription)")
            }
        }
    }

    private static func wipeStore() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first
        guard let dir else { return }
        for name in ["EchoStore.sqlite", "EchoStore.sqlite-shm", "EchoStore.sqlite-wal",
                     "EchoStore.sqlite3", "EchoStore.sqlite3-shm", "EchoStore.sqlite3-wal"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(nil)
                .task {
                    Notifier.shared.requestAuth()
                    if !app.onboarded { showOnboard = true }
                }
                .fullScreenCover(isPresented: $showOnboard) {
                    OnboardView {
                        app.onboarded = true
                        UserDefaults.standard.set(true, forKey: "echo.onboarded")
                        showOnboard = false
                    }
                    .environment(app)
                }
        }
        .modelContainer(container)
    }
}

struct OnboardView: View {
    @Environment(AppState.self) private var app
    var onDone: () -> Void
    @State private var picked = "deepseek"
    @State private var key = ""
    @State private var showKey = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Echo")
                            .font(.system(size: 34, weight: .heavy, design: .rounded)).italic()
                        Text("手机本地的 AI 工作台。\n不上传文件、不经过我们的服务器，你的 Key 直连模型厂商。")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. 选厂商").font(.system(size: 15, weight: .semibold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(vendorPresets.filter { $0.id != "custom" }) { v in
                                Button {
                                    picked = v.id
                                    app.apply(v)
                                } label: {
                                    HStack {
                                        Text(v.name).font(.system(size: 14.5, weight: .medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        Spacer()
                                        if picked == v.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 13)
                                    .background(picked == v.id ? Color.primary.opacity(0.07) : Color(hex: "F6F6F8"),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("2. 粘贴 API Key").font(.system(size: 15, weight: .semibold))
                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-...", text: $key)
                                } else {
                                    SecureField("sk-...", text: $key)
                                }
                            }
                            .font(.system(size: 15, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(hex: "F6F6F8"),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if let v = findPreset(picked), !v.keyURL.isEmpty {
                            Link(v.keyURL, destination: URL(string: v.keyURL)!)
                                .font(.system(size: 13))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("3. 挑模型").font(.system(size: 15, weight: .semibold))
                        FlowChips(items: app.vendor?.models ?? [], selection: $app.settings.model)
                    }

                    Button {
                        app.apiKey = key.trimmed
                        app.saveKey()
                        app.save()
                        onDone()
                    } label: {
                        Text(key.trimmed.isEmpty ? "先跳过，进设置再填" : "开始使用")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 22)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") { onDone() }.foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FlowChips: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(items, id: \.self) { m in
                    Button {
                        selection = m
                    } label: {
                        Text(m)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(selection == m ? Theme.accent.opacity(0.14) : Color(hex: "F6F6F8"),
                                        in: Capsule())
                            .overlay(Capsule().stroke(selection == m ? Theme.accent : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
