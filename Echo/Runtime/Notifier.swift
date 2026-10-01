import UIKit
import UserNotifications
import AVFoundation

@MainActor
final class Notifier: NSObject {
    static let shared = Notifier()

    private var authed = false
    private let synth = AVSpeechSynthesizer()
    private var isSpeaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func requestAuth() {
        guard !authed else { return }
        authed = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func runDone(title: String, body: String) {
        requestAuth()
        let inBackground = UIApplication.shared.applicationState != .active
        if Notifier.settingsHaptics { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        guard inBackground else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    static var settingsHaptics = true

    func tap(_ heavy: Bool = false) {
        guard Notifier.settingsHaptics else { return }
        if heavy { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        else { UISelectionFeedbackGenerator().selectionChanged() }
    }

    func speak(_ text: String) {
        let clean = Self.speakable(text)
        guard !clean.isEmpty else { return }
        if isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: String(clean.prefix(4000)))
        u.rate = 0.5
        u.voice = AVSpeechSynthesisVoice(language: clean.hasCJK ? "zh-CN" : "en-US")
        synth.speak(u)
    }

    func stopSpeaking() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    var speaking: Bool { synth.isSpeaking }

    static func copy(_ s: String) {
        UIPasteboard.general.string = s
    }

    static func paste() -> String { UIPasteboard.general.string ?? "" }

    static func speakable(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: "（代码略）", options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^#{1,6} ", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^\\s*[-*+] ", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(\\*\\*|__)", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^\\)]*\\)", with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var hasCJK: Bool { unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF } }
}

extension Notifier: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
