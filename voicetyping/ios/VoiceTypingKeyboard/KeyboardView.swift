import SwiftUI
import UIKit

struct KeyboardView: View {
    let textDocumentProxy: UITextDocumentProxy
    let advanceToNextInputMode: () -> Void

    @StateObject private var speechManager = SpeechManager()
    @State private var selectedMode: OutputMode = Settings.shared.selectedMode
    @State private var cleanedText: String?
    @State private var isProcessing = false
    @State private var showRaw = false

    private let formatter = LLMFormatter()

    var body: some View {
        VStack(spacing: 4) {
            ModeSelector(selectedMode: $selectedMode)
                .padding(.top, 4)

            TranscriptionPreview(
                rawText: speechManager.transcription,
                cleanedText: cleanedText,
                isProcessing: isProcessing,
                showRaw: showRaw,
                onInsert: insertText
            )
            .onTapGesture {
                if cleanedText != nil { showRaw.toggle() }
            }

            Spacer(minLength: 2)

            HStack(spacing: 0) {
                Button(action: advanceToNextInputMode) {
                    Image(systemName: "globe")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .foregroundColor(.primary)
                }

                Button(action: { textDocumentProxy.insertText(" ") }) {
                    Text("space")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemBackground))
                        .cornerRadius(6)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 4)

                Button(action: { textDocumentProxy.deleteBackward() }) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundColor(.primary)
                }

                Button(action: toggleRecording) {
                    Image(systemName: speechManager.isRecording ? "mic.fill" : "mic")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(speechManager.isRecording ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            HStack {
                Spacer()
                Button(action: { textDocumentProxy.insertText("\n") }) {
                    Text("return")
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(height: 260)
        .background(Color(.systemGray5))
    }

    private func toggleRecording() {
        if speechManager.isRecording {
            let rawText = speechManager.stopRecording()
            processText(rawText)
        } else {
            cleanedText = nil
            showRaw = false
            Task {
                let granted = await speechManager.requestPermissions()
                if granted {
                    speechManager.startRecording()
                }
            }
        }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    private func processText(_ text: String) {
        guard !text.isEmpty else { return }
        isProcessing = true
        Task {
            let result = await formatter.format(text, mode: selectedMode)
            cleanedText = result.cleaned
            isProcessing = false
        }
    }

    private func insertText() {
        guard let text = cleanedText ?? (speechManager.transcription.isEmpty ? nil : speechManager.transcription) else { return }
        textDocumentProxy.insertText(text)
        cleanedText = nil
        speechManager.transcription = ""
    }
}
