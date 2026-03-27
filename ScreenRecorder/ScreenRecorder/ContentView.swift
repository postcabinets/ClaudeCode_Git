import SwiftUI

struct ContentView: View {
    @StateObject private var captureManager = ScreenCaptureManager.shared
    @State private var captureSystemAudio = true
    @State private var captureMicrophone = true
    @State private var lastSavedURL: URL?
    @State private var showSaveSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            if captureManager.permissionGranted {
                // Main controls
                VStack(spacing: 20) {
                    displaySelector
                    audioOptions
                    recordButton
                    statusInfo
                }
                .padding(24)
            } else {
                permissionView
            }

            Spacer()

            // Footer
            if let url = lastSavedURL, showSaveSuccess {
                savedFileInfo(url: url)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ScreenRecorder")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("v0.1.0 — Phase 1 MVP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if captureManager.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())
                    Text(formatDuration(captureManager.recordingDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Display Selector

    private var displaySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("録画対象", systemImage: "display")
                .font(.headline)

            Picker("ディスプレイ", selection: $captureManager.selectedDisplay) {
                ForEach(captureManager.availableDisplays, id: \.displayID) { display in
                    Text("Display \(display.displayID) (\(Int(display.width))×\(Int(display.height)))")
                        .tag(Optional(display))
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await captureManager.refreshContent() }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Audio Options

    private var audioOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("音声", systemImage: "waveform")
                .font(.headline)

            HStack(spacing: 20) {
                Toggle(isOn: $captureSystemAudio) {
                    Label("システム音声", systemImage: "speaker.wave.2")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $captureMicrophone) {
                    Label("マイク", systemImage: "mic")
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            Task {
                if captureManager.isRecording {
                    let url = await captureManager.stopRecording()
                    if let url = url {
                        lastSavedURL = url
                        showSaveSuccess = true
                    }
                } else {
                    showSaveSuccess = false
                    await captureManager.startRecording(
                        captureSystemAudio: captureSystemAudio,
                        captureMicrophone: captureMicrophone
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: captureManager.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title2)
                Text(captureManager.isRecording ? "録画停止" : "録画開始")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(captureManager.isRecording ? .red : .blue)
        .controlSize(.large)
    }

    // MARK: - Status

    private var statusInfo: some View {
        Group {
            if let error = captureManager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("画面収録の権限が必要です")
                .font(.title3)
                .fontWeight(.medium)

            Text("システム設定 > プライバシーとセキュリティ > 画面収録\nで「ScreenRecorder」を許可してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("システム設定を開く") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .buttonStyle(.borderedProminent)

                Button("権限を再確認") {
                    Task { await captureManager.requestPermission() }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Saved File Info

    private func savedFileInfo(url: URL) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("保存済み")
                .fontWeight(.medium)
            Text(url.lastPathComponent)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Finderで開く") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - Double(Int(duration))) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

#Preview {
    ContentView()
        .frame(width: 520, height: 420)
}
