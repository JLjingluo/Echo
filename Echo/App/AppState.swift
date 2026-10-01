import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppState {
    var settings = AppSettings()
    var apiKey = ""
    var onboarded = false
    var appearance: EchoAppearance = .system

    let runtime = AgentRuntime()
    let store = FileStore.shared
    let voice = VoiceInput()

    private let defaults = UserDefaults.standard
    private static let settingsKey = "echo.settings.v1"

    init() {
        load()
        Notifier.settingsHaptics = settings.haptics
    }

    var vendor: VendorPreset? { findPreset(settings.vendorID) }

    var vendorName: String { vendor?.name ?? "自定义" }

    var statusLine: String {
        if apiKey.isEmpty { return "还没填 \(vendorName) 的 Key" }
        return "\(vendorName) · \(settings.model)"
    }

    func load() {
        if let data = defaults.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        }
        apiKey = KeychainStore.key(for: settings.provider, vendor: settings.vendorID)
        onboarded = defaults.bool(forKey: "echo.onboarded")
        appearance = EchoAppearance(rawValue: defaults.string(forKey: "echo.appearance") ?? "") ?? .system
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        defaults.set(appearance.rawValue, forKey: "echo.appearance")
        Notifier.settingsHaptics = settings.haptics
    }

    func saveKey() {
        KeychainStore.setKey(apiKey, for: settings.provider, vendor: settings.vendorID)
    }

    func apply(_ preset: VendorPreset) {
        settings.provider = preset.provider
        settings.vendorID = preset.id
        if !preset.baseURL.isEmpty { settings.baseURL = preset.baseURL }
        if settings.model.isEmpty || !preset.models.contains(settings.model) {
            settings.model = preset.models.first ?? settings.model
        }
        save()
        apiKey = KeychainStore.key(for: preset.provider, vendor: preset.id)
    }

    var canSend: Bool { !apiKey.isEmpty && !settings.model.isEmpty }

    var missingReason: String? {
        if apiKey.isEmpty { return "先填 \(vendorName) 的 API Key" }
        if settings.model.isEmpty { return "先选一个模型" }
        return nil
    }

    var historyLimit: Int { max(4, settings.historyLimit) }
}
