import Foundation
import AVFoundation

final class VideoWriter {
    private let outputURL: URL
    private let videoSize: CGSize
    private let captureMicrophone: Bool

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?

    private var audioEngine: AVAudioEngine?
    private var micBufferQueue: [(CMSampleBuffer)] = []
    private let bufferLock = NSLock()

    private var isWriting = false
    private var sessionStarted = false

    init(outputURL: URL, videoSize: CGSize, captureMicrophone: Bool) {
        self.outputURL = outputURL
        self.videoSize = videoSize
        self.captureMicrophone = captureMicrophone
    }

    // MARK: - Setup

    func startWriting() throws {
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,   // 10 Mbps
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        self.videoInput = videoInput

        // System audio input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000,
        ]

        let systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudioInput.expectsMediaDataInRealTime = true
        writer.add(systemAudioInput)
        self.systemAudioInput = systemAudioInput

        // Microphone audio input
        if captureMicrophone {
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000,
            ]
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            micInput.expectsMediaDataInRealTime = true
            writer.add(micInput)
            self.micAudioInput = micInput
        }

        writer.startWriting()
        self.assetWriter = writer
        self.isWriting = true
        self.sessionStarted = false
    }

    // MARK: - Append samples

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, let writer = assetWriter, writer.status == .writing else { return }
        guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        videoInput.append(sampleBuffer)
    }

    func appendSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, sessionStarted else { return }
        guard let systemAudioInput = systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
        systemAudioInput.append(sampleBuffer)
    }

    func appendMicAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, sessionStarted else { return }
        guard let micAudioInput = micAudioInput, micAudioInput.isReadyForMoreMediaData else { return }
        micAudioInput.append(sampleBuffer)
    }

    // MARK: - Microphone capture via AVAudioEngine

    func startMicrophoneCapture() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            guard let sampleBuffer = self.createSampleBuffer(from: buffer, time: time) else { return }
            self.appendMicAudioSample(sampleBuffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            print("Microphone start failed: \(error)")
        }
    }

    private func createSampleBuffer(from buffer: AVAudioPCMBuffer, time: AVAudioTime) -> CMSampleBuffer? {
        let frameCount = CMItemCount(buffer.frameLength)
        let audioStreamDescription = buffer.format.streamDescription

        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMAudioFormatDescription?

        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: audioStreamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard let desc = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(audioStreamDescription.pointee.mSampleRate)),
            presentationTimeStamp: CMTime(seconds: AVAudioTime.seconds(forHostTime: time.hostTime), preferredTimescale: 48000),
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        if let sampleBuffer = sampleBuffer, let audioBufferList = buffer.audioBufferList.pointee.mBuffers.mData {
            let dataSize = Int(buffer.audioBufferList.pointee.mBuffers.mDataByteSize)
            var blockBuffer: CMBlockBuffer?

            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: dataSize,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataSize,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            if let blockBuffer = blockBuffer {
                CMBlockBufferReplaceDataBytes(
                    with: audioBufferList,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: dataSize
                )
                CMSampleBufferSetDataBuffer(sampleBuffer, newValue: blockBuffer)
            }

            return sampleBuffer
        }

        return nil
    }

    // MARK: - Finish

    func finishWriting() async -> URL? {
        isWriting = false

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        guard let writer = assetWriter, writer.status == .writing else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume(returning: self.outputURL)
                } else {
                    print("Writer finished with error: \(writer.error?.localizedDescription ?? "unknown")")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
