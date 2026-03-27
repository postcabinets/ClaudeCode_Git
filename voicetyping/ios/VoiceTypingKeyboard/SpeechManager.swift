import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechManager: ObservableObject {

    @Published var isRecording = false
    @Published var transcription = ""
    @Published var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            error = "音声認識の許可が必要です"
            return false
        }

        let audioStatus = await AVAudioApplication.requestRecordPermission()
        guard audioStatus else {
            error = "マイクの許可が必要です"
            return false
        }

        return true
    }

    func startRecording() {
        guard !isRecording else { return }

        transcription = ""
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            error = "音声認識が利用できません"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionRequest = request
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let result = result {
                        self.transcription = result.bestTranscription.formattedString
                    }
                    if let taskError = taskError {
                        let nsError = taskError as NSError
                        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                            self.restartRecognitionTask()
                        }
                    }
                }
            }

            isRecording = true
        } catch {
            self.error = "録音を開始できませんでした: \(error.localizedDescription)"
        }
    }

    func stopRecording() -> String {
        guard isRecording else { return transcription }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)

        return transcription
    }

    private func restartRecognitionTask() {
        guard isRecording else { return }

        let currentText = transcription
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    self.transcription = currentText + " " + result.bestTranscription.formattedString
                }
                if let taskError = taskError {
                    let nsError = taskError as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.restartRecognitionTask()
                    }
                }
            }
        }
    }
}
