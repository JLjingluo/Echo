import Foundation
import AVFoundation
import Speech

@MainActor
@Observable
final class VoiceInput {
    var listening = false
    var transcript = ""
    var hint = ""

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func start(language: String) {
        guard !listening else { return }
        transcript = ""
        hint = "正在听…"
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.hint = "没给语音识别权限，去设置里开"
                    return
                }
                AVAudioApplication.requestRecordPermission { ok in
                    Task { @MainActor in
                        guard ok else {
                            self.hint = "没给麦克风权限"
                            return
                        }
                        self.begin(language)
                    }
                }
            }
        }
    }

    private func begin(_ language: String) {
        let locale = Locale(identifier: language)
        guard let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            hint = "这台设备没有该语言的语音识别"
            return
        }
        guard rec.isAvailable else {
            hint = "语音服务当前不可用（要联网）"
            return
        }
        recognizer = rec
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 17.0, *) { req.addsPunctuation = true }
        request = req
        let eng = AVAudioEngine()
        engine = eng
        let input = eng.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else {
            hint = "麦克风格式异常，重开一次试试"
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        eng.prepare()
        do { try eng.start() } catch {
            hint = "麦克风启动失败：\(error.localizedDescription)"
            input.removeTap(onBus: 0)
            return
        }
        task = rec.recognitionTask(with: req) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }
                if let r = result {
                    self.transcript = r.bestTranscription.formattedString
                    if r.isFinal { self.stop() }
                }
                if err != nil { self.stop() }
            }
        }
        listening = true
    }

    func stop() {
        listening = false
        hint = ""
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}
