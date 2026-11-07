import AVFoundation
import Foundation
import Speech

/// Ukrainian dictation for the manual-entry form.
@MainActor
final class VoiceEntryService: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "uk-UA"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isRecording { stop(); return }
        errorMessage = nil
        guard await Self.requestSpeechAuthorization() else {
            errorMessage = "Дозвольте розпізнавання мовлення: Налаштування → FoodLens."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Дозвольте доступ до мікрофона: Налаштування → FoodLens."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Розпізнавання української мови зараз недоступне."
            return
        }
        do {
            try start(with: recognizer)
        } catch {
            teardown()
            errorMessage = "Не вдалося почати запис."
        }
    }

    func stop() {
        guard isRecording else { return }
        // Ending the audio lets the recognizer deliver its final result before the task finishes.
        request?.endAudio()
        task?.finish()
        teardown()
    }

    private func start(with recognizer: SFSpeechRecognizer) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
        Self.installTap(on: node, feeding: request)
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = Self.startRecognition(recognizer: recognizer, request: request) { [weak self] text, finished in
            guard let self else { return }
            if let text { self.transcript = text }
            if finished { self.stop() }
        }
    }

    private func teardown() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // These helpers are nonisolated so their closures are not main-actor-isolated:
    // AVFoundation and Speech call them on background threads.

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func installTap(on node: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func startRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @MainActor @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in onUpdate(text, finished) }
        }
    }
}
