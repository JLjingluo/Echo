import SwiftUI
import WebKit
import QuickLook

struct WorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var files: [WorkspaceFile] = []
    @State private var query = ""
    @State private var preview: RunFile?
    @State private var exportURLs: [URL] = []
    @State private var renameTarget: WorkspaceFile?
    @State private var renameText = ""
    @State private var confirmDelete: WorkspaceFile?
    @State private var confirmWipe = false

    var filtered: [WorkspaceFile] {
        query.trimmed.isEmpty ? files
            : files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    VStack(spacing: 14) {
                        BrandFace(size: 64, seed: 970)
                        Text("工作区还是空的")
                            .font(Hand.display(22))
                            .foregroundStyle(Ink.line)
                        Text("让 Agent 生成文件后，会出现在这里。")
                            .font(Hand.pencil(17))
                            .foregroundStyle(Ink.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HandSearchField(text: $query, prompt: "搜索文件")
                                .padding(.vertical, 10)
                            ForEach(filtered) { f in row(f) }
                            Spacer(minLength: 30)
                        }
                        .padding(.horizontal, Gutter.edge)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("工作区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Ink.paper, for: .navigationBar)
            .background(PaperBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HandIcon(glyph: .close, size: 15, color: Ink.line, seed: 975)
                            .frame(width: 34, height: 34)
                            .overlay(SketchCircle(seed: 976)
                                .stroke(Ink.line, lineWidth: 1.5))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        Button(action: exportAll) {
                            HandIcon(glyph: .folder, size: 18, color: Ink.line, seed: 977)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        SketchRect(seed: 978, corner: 1)
                            .stroke(Ink.faint, lineWidth: 1)
                            .frame(width: 1.2, height: 16)
                        Button(action: shareAll) {
                            HandIcon(glyph: .send, size: 17, color: Ink.line, seed: 979)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        SketchRect(seed: 980, corner: 1)
                            .stroke(Ink.faint, lineWidth: 1)
                            .frame(width: 1.2, height: 16)
                        Button { confirmWipe = true } label: {
                            HandIcon(glyph: .trash, size: 17, color: Ink.danger, seed: 981)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 44)
                    .sketch(seed: 982, capsule: true, double: true)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(files.count) 个文件 · \(ToolOutcome.sizeText(files.reduce(0) { $0 + $1.size }))")
                        .font(Hand.mono(12))
                        .foregroundStyle(Ink.gray)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Ink.paper)
                .overlay(alignment: .top) {
                    SketchRect(seed: 66, corner: 1)
                        .stroke(Ink.faint, lineWidth: 1)
                }
            }
            .overlay {
                if !exportURLs.isEmpty {
                    FileExporter(urls: exportURLs) { _ in exportURLs = [] }.ignoresSafeArea()
                }
            }
            .sheet(item: $preview) { FilePreviewView(file: $0) }
            .alert("重命名", isPresented: .init(
                get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("新文件名", text: $renameText)
                Button("好") { doRename() }
                Button("取消", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog("删除这个文件？", isPresented: .init(
                get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) { doDelete() }
                Button("取消", role: .cancel) { confirmDelete = nil }
            }
            .confirmationDialog("清空整个工作区？", isPresented: $confirmWipe,
                                titleVisibility: .visible) {
                Button("全部删除", role: .destructive) { wipe() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("\(files.count) 个文件会被删掉，撤销不了。已导出到「文件」App 的不受影响。")
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }

    private func row(_ f: WorkspaceFile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HandIcon(glyph: f.isDir ? .folder : fileGlyph(f.name), size: 19,
                         color: Ink.gray, seed: 985)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name)
                        .font(Hand.body(16))
                        .foregroundStyle(Ink.line)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(f.sizeText) · \(Self.dateFmt.string(from: f.modified))")
                        .font(Hand.mono(11))
                        .foregroundStyle(Ink.faint)
                }
                Spacer()
                HandIcon(glyph: .chevron, size: 12, color: Ink.faint, seed: 986)
                    .rotationEffect(.degrees(-90))
            }
            .frame(minHeight: 54)
            SketchRect(seed: 987, corner: 1, wobble: 0.6)
                .stroke(Ink.faint.opacity(0.4), lineWidth: 1)
                .frame(height: 1)
                .padding(.leading, 36)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            preview = RunFile(name: f.name, path: f.url.path, size: f.size, preview: "")
        }
        .contextMenu {
            Button("分享", systemImage: "square.and.arrow.up") { ShareHelper.share(items: [f.url]) }
            Button("导出到「文件」App", systemImage: "folder") { exportURLs = [f.url] }
            Button("重命名", systemImage: "pencil") { renameText = f.name; renameTarget = f }
            Button("删除", role: .destructive) { confirmDelete = f }
        }
    }

    private func fileGlyph(_ name: String) -> HandGlyph {
        switch icon(name) {
        case "globe", "curlybraces", "tablecells": return .search
        case "folder": return .folder
        case "trash": return .trash
        default: return .doc
        }
    }

    private func icon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt", "log": return "doc.text"
        case "swift", "js", "ts", "py", "go", "rs", "java", "c", "h", "cpp":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "css": return "globe"
        case "json", "yml", "yaml", "toml", "ini": return "curlybraces"
        case "csv", "tsv": return "tablecells"
        case "png", "jpg", "jpeg", "gif", "pdf": return "doc.richtext"
        case "": return "folder"
        default: return "doc"
        }
    }

    private func reload() {
        files = FileStore.shared.list()
    }

    private func exportAll() {
        let urls = FileStore.shared.allURLs()
        guard !urls.isEmpty else { return }
        exportURLs = urls
    }

    private func shareAll() {
        let urls = FileStore.shared.allURLs()
        guard !urls.isEmpty else { return }
        ShareHelper.share(items: urls)
    }

    private func wipe() {
        for u in FileStore.shared.allURLs() { try? FileManager.default.removeItem(at: u) }
        reload()
    }

    private func doRename() {
        guard let f = renameTarget, !renameText.trimmed.isEmpty else { return }
        try? FileStore.shared.move(from: f.name, to: renameText.trimmed)
        renameTarget = nil
        reload()
    }

    private func doDelete() {
        guard let f = confirmDelete else { return }
        try? FileStore.shared.delete(f.name)
        confirmDelete = nil
        reload()
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

struct FilePreviewView: View {
    let file: RunFile
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var image: UIImage?
    @State private var dirty = false
    @State private var exportURLs: [URL] = []
    @State private var note = ""

    var url: URL { URL(fileURLWithPath: file.path) }
    var isWeb: Bool { ["html", "htm", "svg", "xml"].contains(file.ext) }

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                } else if isWeb {
                    WebPreview(url: url)
                        .id(url)
                } else if !file.isText {
                    QuickLookPreview(url: url)
                        .id(url)
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 13.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .onChange(of: text) { _, _ in dirty = true }
                }
            }
            .padding(.horizontal, isWeb ? 0 : 6)
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("导出到「文件」App", systemImage: "folder") { exportURLs = [url] }
                        Button("分享", systemImage: "square.and.arrow.up") { ShareHelper.share(items: [url]) }
                        Button("复制全文", systemImage: "doc.on.doc") { Notifier.copy(text) }
                        if dirty {
                            Button("保存修改", systemImage: "checkmark") { save() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if !exportURLs.isEmpty {
                    FileExporter(urls: exportURLs) { ok in
                        exportURLs = []
                        note = ok ? "已导出" : "已取消"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { note = "" }
                    }
                    .ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .sketch(seed: 6, capsule: true, color: Ink.gray)
                        .padding(.bottom, 6)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if ["png", "jpg", "jpeg", "gif", "heic"].contains(file.ext) {
            image = UIImage(contentsOfFile: file.path)
        } else {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? "（这个文件读不出来，可能是二进制）"
        }
    }

    private func save() {
        try? FileStore.shared.write((url.path as NSString).lastPathComponent, text)
        dirty = false
        note = "已保存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { note = "" }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ c: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            c.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        final class FileItem: NSObject, QLPreviewItem {
            let u: URL
            init(_ u: URL) { self.u = u }
            var previewItemURL: URL? { u }
            var previewItemTitle: String? { u.lastPathComponent }
        }

        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in _: QLPreviewController) -> Int { 1 }
        func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
            FileItem(url)
        }
    }
}

struct WebPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.isOpaque = false
        v.backgroundColor = .systemBackground
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

struct ContentUnavailableCompat: View {
    let title: String
    let sub: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(sub).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
