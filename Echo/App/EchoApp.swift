import SwiftUI
import SwiftData

@main
struct EchoApp: App {
    @State private var app = AppState()
    @State private var showOnboard = false
    private let container: ModelContainer

    init() {
        EchoFont.register()
        container = Self.makeContainer()
        Self.excludeStoreFromBackup()
    }

    private static func excludeStoreFromBackup() {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where name.hasPrefix("EchoStore") {
            var url = dir.appendingPathComponent(name)
            try? url.setResourceValues(values)
        }
    }

    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration("EchoStore", isStoredInMemoryOnly: false)
        if let c = try? ModelContainer(for: ChatSession.self, ChatMessage.self, MsgBlock.self,
                                       configurations: config) {
            return c
        }
        wipeStore()
        if let c = try? ModelContainer(for: ChatSession.self, ChatMessage.self, MsgBlock.self,
                                       configurations: config) {
            return c
        }
        EchoState.storeDegraded = true
        let mem = ModelConfiguration("EchoStore", isStoredInMemoryOnly: true)
        return try! ModelContainer(for: ChatSession.self, ChatMessage.self, MsgBlock.self,
                                   configurations: mem)
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
                .preferredColorScheme(app.appearance.scheme)
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
    @Environment(\.colorScheme) private var scheme
    var onDone: () -> Void
    @State private var showModel = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Echo")
                            .font(EchoFont.wordmark(30))
                            .foregroundStyle(EchoTheme.primaryText(scheme))
                        Text("不经过我们的服务器：会话、文件、Key 都只在你手机上；调用模型时直连你选的那家厂商。图片会以 base64 发给该厂商做识别，联网抓取会走公开搜索引擎。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }

                Section("1. 厂商与 Key") {
                    Button { showModel = true } label: {
                        HStack {
                            Text("厂商与模型")
                            Spacer()
                            Text(app.settings.model.isEmpty ? app.vendorName : "\(app.vendorName) · \(app.settings.model)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    HStack {
                        Group {
                            if app.apiKey.isEmpty {
                                TextField("粘贴 API Key", text: $app.apiKey)
                            } else {
                                SecureField("API Key", text: $app.apiKey)
                            }
                        }
                        .font(.system(.subheadline, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: app.apiKey) { _, _ in app.saveKey() }
                    }
                    if let v = app.vendor, !v.keyURL.isEmpty {
                        Link(destination: URL(string: v.keyURL)!) {
                            HStack(spacing: 6) {
                                EchoIcon("arrow.up.right.square", size: 14)
                                Text("去 \(v.name) 控制台创建 Key")
                            }
                            .font(.footnote)
                        }
                    }
                    if let v = app.vendor, !v.note.isEmpty {
                        Text(v.note).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    InkButton("开始使用", style: .prominent) {
                        app.apiKey = app.apiKey.trimmed
                        app.saveKey()
                        app.save()
                        onDone()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                } footer: {
                    Text("Key 只存本机钥匙串，切厂商不会丢。没 Key 也可以先跳过，进去后随时填。")
                }
            }
            .navigationTitle("欢迎")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") { onDone() }.foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showModel) { ModelPickerSheet() }
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
