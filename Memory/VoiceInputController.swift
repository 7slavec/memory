import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class VoiceInputController: ObservableObject {
    private static weak var activeRecorder: VoiceInputController?
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var initialText = ""
    private var hasAudioTap = false
    private var generation = UUID()
    private var isStarting = false
    private let speechAuthorization: (() async -> Bool)?
    private let microphoneAuthorization: (() async -> Bool)?

    init(speechAuthorization: (() async -> Bool)? = nil,
         microphoneAuthorization: (() async -> Bool)? = nil) {
        self.speechAuthorization = speechAuthorization
        self.microphoneAuthorization = microphoneAuthorization
    }

    func toggle(currentText: String) async {
        if isListening {
            stop()
        } else {
            guard !isStarting else { return }
            await start(currentText: currentText)
        }
    }

    func stop() {
        if Self.activeRecorder === self { Self.activeRecorder = nil }
        generation = UUID()
        isStarting = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
#endif
    }

    private func start(currentText: String) async {
        if let active = Self.activeRecorder, active !== self {
            errorMessage = "Диктовка уже идёт в другом окне Norka. Сначала завершите её."
            return
        }
        stop()
        Self.activeRecorder = self
        let requestID = generation
        isStarting = true
        defer {
            if generation == requestID {
                isStarting = false
                if !isListening, Self.activeRecorder === self { Self.activeRecorder = nil }
            }
        }
        errorMessage = nil

        let speechAllowed = await requestSpeechAuthorization()
        guard generation == requestID, !Task.isCancelled else { return }
        guard speechAllowed else {
            errorMessage = "Разрешите Norka распознавать речь в системных настройках."
            return
        }
        let microphoneAllowed = await requestMicrophoneAuthorization()
        guard generation == requestID, !Task.isCancelled else { return }
        guard microphoneAllowed else {
            errorMessage = "Разрешите Norka доступ к микрофону в системных настройках."
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Распознавание речи сейчас недоступно. Попробуйте ещё раз чуть позже."
            return
        }

        initialText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = initialText

        do {
#if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
#endif

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.taskHint = .dictation
            request.contextualStrings = [
                "сегодня", "завтра", "послезавтра",
                "утром", "днём", "вечером", "ночью",
                "полдесятого", "пол одиннадцатого"
            ]
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0 else {
                errorMessage = "Не удалось подключить микрофон."
                recognitionRequest = nil
                return
            }

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: recordingFormat
            ) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            hasAudioTap = true

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.generation == requestID else { return }
                    if let spokenText = result?.bestTranscription.formattedString,
                       !spokenText.isEmpty {
                        self.transcript = self.combinedText(with: spokenText)
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            stop()
            errorMessage = "Не удалось начать запись. Проверьте микрофон и попробуйте ещё раз."
        }
    }

    private func combinedText(with spokenText: String) -> String {
        initialText.isEmpty ? spokenText : "\(initialText) \(spokenText)"
    }

    private func requestSpeechAuthorization() async -> Bool {
        if let speechAuthorization { return await speechAuthorization() }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        if let microphoneAuthorization { return await microphoneAuthorization() }
#if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
#elseif os(macOS)
        return await AVCaptureDevice.requestAccess(for: .audio)
#else
        return false
#endif
    }
}
