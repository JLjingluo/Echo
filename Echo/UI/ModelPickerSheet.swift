import SwiftUI

struct ModelPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showAll = false
    @State private var loading = false
    @State private var note = ""
    @State private var fetched: [ModelEntry] = []
    @State private var fetchedAt: Date?
    @State private var manual = ""

    private var visible: [ModelEntry] {
        var list = fetched
        if !showAll { list = list.filter { ModelCatalog.isChatModel($0.id) } }
        let q = query.trimmed.lowercased()
        if !q.isEmpty { list = list.filter { $0.id.lowercased().contains(q) } }
        let current = app.settings.model
        if !current.isEmpty, !list.contains(where: { $0.id == current }) {
            list.insert(ModelEntry(id: current), at: 0)
        }
        return list
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HandSectionHeader(text: "厂商")
                    ForEach(Array(vendorPresets.enumerated()), id: \.offset) { i, v in
                        pickRow(title: v.name,
                                detail: v.baseURL.isEmpty ? "自己填接口地址" : v.baseURL,
                                selected: app.settings.vendorID == v.id,
                                seed: UInt64(840 + i)) { applyVendor(v) }
                    }

                    HandSectionHeader(text: "API Key（只存本机钥匙串）")
                    keyField
                    if let url = URL(string: app.vendor?.keyURL ?? "") {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            HStack(spacing: 6) {
                                HandIcon(glyph: .sparkle, size: 13, color: Ink.accent, seed: 860)
                                Text("去 \(app.vendorName) 控制台创建 Key")
                                    .font(Hand.body(14))
                                    .foregroundStyle(Ink.accent)
                            }
                            .frame(minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                    if let n = app.vendor?.note, !n.isEmpty {
                        Text(n).font(Hand.body(12)).foregroundStyle(Ink.gray)
                            .padding(.vertical, 4)
                    }

                    HandSectionHeader(text: "模型（\(visible.count)）")
                    HStack(spacing: 10) {
                        Button { Task { await load() } } label: {
                            HStack(spacing: 6) {
                                if loading {
                                    RedrawSpinner(size: 14)
                                    Text("读取中…")
                                } else {
                                    HandIcon(glyph: .search, size: 14, color: Ink.line, seed: 861)
                                    Text(fetched.isEmpty ? "读取模型列表" : "重新读取")
                                }
                            }
                            .font(Hand.body(15).weight(.semibold))
                            .foregroundStyle(Ink.line)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RedrawButtonStyle(shape: SketchCapsule(seed: 862), double: true))
                        .disabled(loading)
                        Spacer()
                        if let at = fetchedAt {
                            Text(at, style: .time)
                                .font(Hand.mono(12))
                                .foregroundStyle(Ink.faint)
                        }
                    }
                    .padding(.vertical, 8)

                    HStack(spacing: 10) {
                        Text("显示非对话模型（图形/语音/向量）")
                            .font(Hand.body(14))
                            .foregroundStyle(Ink.gray)
                        Spacer()
                        HandToggle(isOn: $showAll, seed: 863)
                    }
                    .frame(minHeight: 44)

                    if !note.isEmpty {
                        HStack(spacing: 8) {
                            HandIcon(glyph: .sparkle, size: 14, color: Ink.danger, seed: 864)
                            Text(note).font(Hand.body(13)).foregroundStyle(Ink.danger)
                        }
                        .padding(.vertical, 6)
                    }

                    HandSearchField(text: $query, prompt: "搜模型名")
                        .padding(.vertical, 8)

                    modelRows

                    HandSectionHeader(text: "手动填模型名")
                    HStack(spacing: 8) {
                        TextField("例如 gpt-4o-mini", text: $manual)
                            .font(Hand.mono(14))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button { useManual() } label: {
                            Text("用这个")
                                .font(Hand.body(14).weight(.semibold))
                                .foregroundStyle(manual.trimmed.isEmpty ? Ink.faint : Ink.accent)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .sketch(seed: 865, capsule: true,
                                        color: manual.trimmed.isEmpty ? Ink.faint : Ink.accent,
                                        width: 1.4)
                        }
                        .buttonStyle(.plain)
                        .disabled(manual.trimmed.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .sketch(seed: 866, capsule: true, color: Ink.faint, width: 1.3)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("接口地址（Base URL）")
                            .font(Hand.body(13)).foregroundStyle(Ink.gray)
                        TextField("https://…", text: $app.settings.baseURL)
                            .font(Hand.mono(13))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .sketch(seed: 867, capsule: true, color: Ink.faint, width: 1.3)
                        Text("只支持 https。填 http 会被系统直接拦掉，报出来就是「连不上厂商」。")
                            .font(Hand.body(12)).foregroundStyle(Ink.gray)
                    }
                    .padding(.top, 10)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Gutter.edge)
            }
            .scrollIndicators(.hidden)
            .background(Ink.paper.ignoresSafeArea())
            .overlay { PaperGrain(density: 400).ignoresSafeArea() }
            .navigationTitle("厂商与模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Ink.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.save(); dismiss() } label: {
                        Text("完成").font(Hand.body(16).weight(.semibold))
                            .foregroundStyle(Ink.line)
                    }
                }
            }
        }
        .onAppear(perform: start)
    }

    @ViewBuilder private var modelRows: some View {
        if visible.isEmpty && !loading {
            Text(presetNames.isEmpty
                 ? "还没有模型。填好 Key 点上面「读取模型列表」。"
                 : "还没读取，先显示内置的 \(presetNames.count) 个。")
                .font(Hand.body(14))
                .foregroundStyle(Ink.gray)
                .padding(.vertical, 8)
            ForEach(Array(presetNames.enumerated()), id: \.offset) { i, name in
                pickRow(title: name, detail: "", selected: app.settings.model == name,
                        seed: UInt64(870 + i)) { pick(name) }
            }
        } else {
            ForEach(Array(visible.enumerated()), id: \.element.id) { i, m in
                pickRow(title: m.id, detail: detailText(m),
                        selected: app.settings.model == m.id,
                        seed: UInt64(880 + i)) { pick(m.id) }
            }
        }
    }

    private func pickRow(title: String, detail: String, selected: Bool,
                         seed: UInt64, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    SketchCircle(seed: seed, open: false)
                        .stroke(selected ? Ink.accent : Ink.faint, lineWidth: 1.5)
                    if selected {
                        HandIcon(glyph: .check, size: 12, color: Ink.accent, seed: seed &+ 1)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Hand.auto(title, 16).weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Ink.line : Ink.gray)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Hand.body(12))
                            .foregroundStyle(Ink.faint)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var keyField: some View {
        @Bindable var app = app
        HStack(spacing: 8) {
            HandIcon(glyph: .sparkle, size: 15, color: Ink.gray, seed: 850)
            Group {
                if app.apiKey.isEmpty {
                    TextField("粘贴这个厂商的 API Key", text: $app.apiKey)
                } else {
                    SecureField("API Key", text: $app.apiKey)
                }
            }
            .font(Hand.mono(13))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: app.apiKey) { _, _ in app.saveKey() }
            if !app.apiKey.isEmpty {
                Button { clearKey() } label: {
                    HandIcon(glyph: .close, size: 12, color: Ink.gray, seed: 851)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .sketch(seed: 852, capsule: true, color: Ink.faint, width: 1.3)
    }

    private var presetNames: [String] { app.vendor?.models ?? [] }

    private func detailText(_ m: ModelEntry) -> String {
        if NoToolMemory.contains(m.id) {
            return m.owner.isEmpty ? "曾被记为不调工具 · 选它可清除"
                : "\(m.owner) · 曾被记为不调工具 · 选它可清除"
        }
        return m.owner
    }

    private func applyVendor(_ v: VendorPreset) {
        app.apply(v)
        reloadCache()
    }

    private func clearKey() {
        app.apiKey = ""
        app.saveKey()
    }

    private func useManual() {
        let m = manual.trimmed
        if !m.isEmpty { pick(m) }
    }

    private func start() {
        reloadCache()
        if fetched.isEmpty && !app.apiKey.trimmed.isEmpty {
            Task { await load() }
        }
    }

    private func reloadCache() {
        if let s = ModelCatalog.load(vendorID: app.settings.vendorID) {
            fetched = s.models
            fetchedAt = s.fetchedAt
        } else {
            fetched = []
            fetchedAt = nil
        }
        note = ""
    }

    private func load() async {
        let key = app.apiKey.trimmed
        guard !key.isEmpty else {
            note = "先填 Key 才能读取模型列表"
            return
        }
        loading = true
        note = ""
        defer { loading = false }
        do {
            let list = try await ModelCatalog.fetch(base: app.settings.trimmedBaseURL,
                                                    provider: app.settings.provider, key: key)
            ModelCatalog.save(vendorID: app.settings.vendorID, list)
            fetched = list
            fetchedAt = .now
        } catch {
            note = Self.explain(error)
        }
    }

    private func pick(_ model: String) {
        NoToolMemory.forget(model)
        app.settings.model = model
        app.save()
        Notifier.shared.tap()
        dismiss()
    }

    static func explain(_ e: Error) -> String {
        if case let .http(code, body)? = e as? ChatError {
            let b = body.lowercased()
            switch code {
            case 401, 403:
                return "Key 不对或没权限（\(code)）。检查有没有多复制空格、是不是这个厂商的 Key。"
            case 404:
                return "这个接口地址没有模型列表接口（404）。可以手动填模型名。"
            default:
                if b.contains("invalid_api_key") || b.contains("apikey") {
                    return "厂商说 Key 无效。重新粘贴一次试试。"
                }
                return "读取失败（\(code)）：" + body.clamped(160)
            }
        }
        if e is URLError { return "连不上厂商，检查网络或接口地址。" }
        return "读取失败：" + e.localizedDescription.clamped(160)
    }
}
