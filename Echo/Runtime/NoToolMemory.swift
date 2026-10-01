import Foundation

enum NoToolMemory {
    private static let storeKey = "echo.modelNoTools"

    static var all: [String] { UserDefaults.standard.stringArray(forKey: storeKey) ?? [] }

    static func contains(_ model: String) -> Bool {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return false }
        return all.contains(m)
    }

    static func remember(_ model: String) {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        var a = all
        guard !a.contains(m) else { return }
        a.append(m)
        UserDefaults.standard.set(a, forKey: storeKey)
    }

    static func forget(_ model: String) {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var a = all
        guard a.contains(m) else { return }
        a.removeAll { $0 == m }
        UserDefaults.standard.set(a, forKey: storeKey)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: storeKey) }
}
