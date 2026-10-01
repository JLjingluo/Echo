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
        NavigationStack {
            List {
                vendorSection
                keySection
                modelSection
                manualSection
            }
            .searchable(text: $query, prompt: "搜模型")
            .listStyle(.insetGrouped)
            .navigationTitle("厂商与模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { app.save(); dismiss() }
                }
            }
        }
        .onAppear(perform: start)
    }

    @ViewBuilder private var vendorSection: some View {
        Section("厂商") {
            ForEach(vendorPresets) { v in
                SelectionRow(title: v.name,
                             detail: v.baseURL.isEmpty ? "自己填接口地址" : v.baseURL,
                             isSelected: app.settings.vendorID == v.id) {
                    applyVendor(v)
                }
            }
        }
    }

    @ViewBuilder private var keySection: some View {
        @Bindable var app = app
        Section {
            keyField
            if let url = URL(string: app.vendor?.keyURL ?? "") {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        EchoIcon("arrow.up.right.square", size: 14)
                        Text("去 \(app.vendorName) 控制台创建 Key")
                    }
                    .font(.footnote)
                }
            }
            if let n = app.vendor?.note, !n.isEmpty {
                Text(n).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("API Key（只存本机钥匙串）")
        }
    }

    @ViewBuilder private var keyField: some View {
        @Bindable var app = app
        HStack(spacing: 10) {
            EchoIcon("key.horizontal", size: 16).foregroundStyle(.secondary)
            Group {
                if app.apiKey.isEmpty {
                    TextField("粘贴这个厂商的 API Key", text: $app.apiKey)
                } else {
                    SecureField("API Key", text: $app.apiKey)
                }
            }
            .font(.system(.subheadline, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: app.apiKey) { _, _ in app.saveKey() }
            if !app.apiKey.isEmpty {
                Button { clearKey() } label: {
                    EchoIcon("xmark.circle.fill", size: 16).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var modelSection: some View {
        Section {
            fetchRow
            Toggle("显示非对话模型（图形/语音/向量）", isOn: $showAll)
                .font(.subheadline)
            if !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.red)
            }
            modelRows
        } header: {
            Text("模型（\(visible.count)）")
        } footer: {
            Text("读取走的是厂商自己的 /models 接口，不经过任何第三方。")
        }
    }

    @ViewBuilder private var fetchRow: some View {
        HStack(spacing: 10) {
            Button { Task { await load() } } label: {
                HStack(spacing: 6) {
                    if loading {
                        ProgressView().controlSize(.small)
                        Text("读取中…")
                    } else {
                        EchoIcon("arrow.clockwise", size: 14)
                        Text(fetched.isEmpty ? "读取模型列表" : "重新读取")
                    }
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(loading)
            Spacer()
            if let at = fetchedAt {
                Text(at, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private var modelRows: some View {
        if visible.isEmpty && !loading {
            Text(presetNames.isEmpty
                 ? "还没有模型。填好 Key 点上面「读取模型列表」。"
                 : "还没读取，先显示内置的 \(presetNames.count) 个。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(presetNames, id: \.self) { name in
                SelectionRow(title: name, detail: "",
                             isSelected: app.settings.model == name) { pick(name) }
            }
        } else {
            ForEach(visible) { m in
                SelectionRow(title: m.id, detail: detailText(m),
                             isSelected: app.settings.model == m.id) { pick(m.id) }
            }
        }
    }

    @ViewBuilder private var manualSection: some View {
        @Bindable var app = app
        Section {
            HStack {
                TextField("例如 gpt-4o-mini", text: $manual)
                    .font(.system(.subheadline, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { useManual() } label: { Text("用这个") }
                    .disabled(manual.trimmed.isEmpty)
            }
            LabeledContent("接口地址（Base URL）") {
                TextField("", text: $app.settings.baseURL, prompt: Text("https://..."))
                    .multilineTextAlignment(.trailing)
                    .font(.system(.caption, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("手动填模型名")
        } footer: {
            Text("接口地址只支持 https。填 http 会被系统直接拦掉，报出来就是「连不上厂商」。")
        }
    }

    private var presetNames: [String] { app.vendor?.models ?? [] }

    private func detailText(_ m: ModelEntry) -> String {
        if NoToolMemory.contains(m.id) {
            return m.owner.isEmpty ? "曾被记为不能调工具，选它即清除"
                : "\(m.owner) · 曾被记为不能调工具，选它即清除"
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

struct SelectionRow: View {
    let title: String
    var detail: String = ""
    let isSelected: Bool
    var working: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    EchoIcon("checkmark", size: 16, weight: .semibold)
                        .opacity(isSelected && !working ? 1 : 0)
                    if working { ProgressView().controlSize(.small) }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
