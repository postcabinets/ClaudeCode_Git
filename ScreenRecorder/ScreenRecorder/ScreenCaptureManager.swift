import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject {
    static let shared = ScreenCaptureManager()

    @Published var isRecording = false
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var selectedDisplay: SCDisplay?
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionGranted = false
    @Published var errorMessage: String?

    private var stream: SCStream?
    private var videoWriter: VideoWriter?
    private var durationTimer: Timer?

    override init() {
        super.init()
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            availableDisplays = content.displays
            availableWindows = content.windows.filter { $0.isOnScreen && $0.frame.width > 100 }
            selectedDisplay = content.displays.first
            permissionGranted = true
            errorMessage = nil
        } catch {
            permissionGranted = false
            errorMessage = "画面収録の権限がありません。システム設定 > プライバシーとセキュリティ > 画面収録 で許可してください。"
        }
    }

    func refreshContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            availableDisplays = content.displays
            availableWindows = content.windows.filter { $0.isOnScreen && $0.frame.width > 100 }
        } catch {
            errorMessage = "画面情報の取得に失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - Recording

    func startRecording(captureSystemAudio: Bool, captureMicrophone: Bool) async {
        guard let display = selectedDisplay else {
            errorMessage = "ディスプレイが選択されていません"
            return
        }

        do {
            // Configure stream
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()

            config.width = Int(display.width) * 2  // Retina
            config.height = Int(display.height) * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60fps
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            // Audio
            config.capturesAudio = captureSystemAudio
            if captureSystemAudio {
                config.sampleRate = 48000
                config.channelCount = 2
            }

            // Set up video writer
            let outputURL = generateOutputURL()
            let videoSize = CGSize(width: config.width, height: config.height)
            videoWriter = VideoWriter(outputURL: outputURL, videoSize: videoSize, captureMicrophone: captureMicrophone)
            try videoWriter?.startWriting()

            // Create and start stream
            let stream = SCStream(filter: filter, configuration: config, delegate: self)

            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

            if captureSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            }

            try await stream.startCapture()
            self.stream = stream

            // Start microphone if needed
            if captureMicrophone {
                videoWriter?.startMicrophoneCapture()
            }

            isRecording = true
            recordingDuration = 0
            errorMessage = nil

            // Duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 0.1
                }
            }

        } catch {
            errorMessage = "録画開始に失敗: \(error.localizedDescription)"
            videoWriter = nil
        }
    }

    func stopRecording() async -> URL? {
        durationTimer?.invalidate()
        durationTimer = nil

        do {
            try await stream?.stopCapture()
        } catch {
            // Stream may already be stopped
        }
        stream = nil

        let url = await videoWriter?.finishWriting()
        videoWriter = nil
        isRecording = false
        return url
    }

    // MARK: - Helpers

    private func generateOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "ScreenRecording_\(timestamp).mp4"

        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let recordingsDir = moviesDir.appendingPathComponent("ScreenRecorder", isDirectory: true)

        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        return recordingsDir.appendingPathComponent(filename)
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "録画が停止しました: \(error.localizedDescription)"
            self.isRecording = false
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            videoWriter?.appendVideoSample(sampleBuffer)
        case .audio:
            videoWriter?.appendSystemAudioSample(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}
