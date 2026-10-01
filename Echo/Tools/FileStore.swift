import Foundation

struct WorkspaceFile: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let url: URL
    let size: Int
    let modified: Date
    let isDir: Bool

    var sizeText: String {
        if isDir { return "-" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }
}

enum FileStoreError: LocalizedError {
    case badName(String)
    case notFound(String)
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .badName(let n): return "非法文件名：\(n)"
        case .notFound(let n): return "文件不存在：\(n)"
        case .tooLarge(let n): return "文件过大：\(n)"
        }
    }
}

@MainActor
final class FileStore {
    static let shared = FileStore()

    let root: URL

    private init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent("Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(for name: String) throws -> URL {
        let cleaned = normalize(name)
        guard !cleaned.isEmpty else { throw FileStoreError.badName(name) }
        guard !cleaned.contains("..") else { throw FileStoreError.badName(name) }
        let parts = cleaned.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { throw FileStoreError.badName(name) }
        let sub = parts.dropLast()
        if sub.contains("..") { throw FileStoreError.badName(name) }
        let target = sub.reduce(root) { $0.appendingPathComponent($1) }
            .appendingPathComponent(parts.last ?? "untitled.txt")
        return target
    }

    private func normalize(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\\", with: "/")
        while s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasPrefix("/") { s.removeFirst() }
        s = s.replacingOccurrences(of: " ", with: "-")
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { allowed.contains($0) || $0.value > 127 }))
        if s.isEmpty { s = "untitled.txt" }
        return s
    }

    @discardableResult
    func write(_ name: String, _ content: String) throws -> URL {
        let target = try url(for: name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try content.data(using: .utf8)?.write(to: target, options: .atomic)
        return target
    }

    @discardableResult
    func writeData(_ name: String, _ data: Data) throws -> URL {
        let target = try url(for: name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return target
    }

    func read(_ name: String, maxBytes: Int = 200_000) throws -> String {
        let target = try url(for: name)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw FileStoreError.notFound(name)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
        let size = (attrs?[.size] as? Int) ?? 0
        if size > maxBytes {
            let head = try FileHandle(forReadingFrom: target)
            defer { try? head.close() }
            let data = head.readData(ofLength: maxBytes)
            return String(decoding: data, as: UTF8.self) + "\n…(已截断，共 \(size) 字节)"
        }
        return String(decoding: try Data(contentsOf: target), as: UTF8.self)
    }

    func exists(_ name: String) -> Bool {
        guard let u = try? url(for: name) else { return false }
        return FileManager.default.fileExists(atPath: u.path)
    }

    func list(_ subdir: String = "") -> [WorkspaceFile] {
        let base: URL
        if subdir.isEmpty {
            base = root
        } else if let u = try? url(for: subdir) {
            base = u
        } else {
            return []
        }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: base,
                                                      includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        return items.map { u in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = v?.isDirectory ?? false
            return WorkspaceFile(name: u.lastPathComponent, url: u,
                                 size: isDir ? 0 : (v?.fileSize ?? 0),
                                 modified: v?.contentModificationDate ?? .distantPast,
                                 isDir: isDir)
        }.sorted { $0.modified > $1.modified }
    }

    func allURLs(recursive: Bool = true) -> [URL] {
        let fm = FileManager.default
        if recursive, let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                            options: [.skipsHiddenFiles]) {
            return e.compactMap { $0 as? URL }
                .filter { !((try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? true) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return list().filter { !$0.isDir }.map(\.url)
    }

    @discardableResult
    func delete(_ name: String) throws -> Bool {
        let target = try url(for: name)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw FileStoreError.notFound(name)
        }
        try FileManager.default.removeItem(at: target)
        return true
    }

    @discardableResult
    func move(from: String, to: String) throws -> URL {
        let src = try url(for: from)
        let dst = try url(for: to)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw FileStoreError.notFound(from)
        }
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: src, to: dst)
        return dst
    }

    func totalBytes() -> Int {
        let fm = FileManager.default
        return allURLs().reduce(0) { sum, u in
            let n = (try? fm.attributesOfItem(atPath: u.path))?[.size] as? Int
            return sum + (n ?? 0)
        }
    }
}
