import ScreenCaptureKit
import AVFoundation
import CoreMedia

class RecordingEngine: NSObject, ObservableObject, SCStreamOutput {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    private let videoQueue = DispatchQueue(label: "com.crustcapture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.crustcapture.audio", qos: .userInteractive)

    private var firstVideoTimestamp: CMTime?
    private var firstAudioTimestamp: CMTime?
    private var lastVideoBuffer: CMSampleBuffer?
    private var isRecording = false
    private var recordingStartTime: Date?

    private var videoURL: URL?
    private var width: Int = 0
    private var height: Int = 0
    private var frameRate: Int = 60

    @Published var duration: TimeInterval = 0
    private var durationTimer: Timer?

    func startRecording(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        videoURL: URL
    ) async throws {
        self.videoURL = videoURL
        self.width = configuration.width
        self.height = configuration.height

        // Set up AVAssetWriter
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 50_000_000,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: "HEVC_Main_AutoLevel" as String
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256000
        ]

        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        writer.add(vInput)
        writer.add(aInput)

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput

        // Reset timestamps
        firstVideoTimestamp = nil
        firstAudioTimestamp = nil
        lastVideoBuffer = nil

        // Start the stream
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream.startCapture()
        self.stream = stream
        self.isRecording = true
        self.recordingStartTime = Date()

        // Duration timer on main thread
        await MainActor.run {
            self.duration = 0
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.recordingStartTime else { return }
                Task { @MainActor in
                    self.duration = Date().timeIntervalSince(start)
                }
            }
        }
    }

    func stopRecording() async -> RecordingSession? {
        guard isRecording else { return nil }
        isRecording = false

        let finalDuration = await MainActor.run { () -> TimeInterval in
            durationTimer?.invalidate()
            durationTimer = nil
            return duration
        }

        // Stop stream first
        if let stream = stream {
            try? await stream.stopCapture()
        }
        stream = nil

        // Drain both queues to ensure all in-flight buffer callbacks complete
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            videoQueue.async {
                self.audioQueue.async {
                    continuation.resume()
                }
            }
        }

        guard let writer = assetWriter else { return nil }

        // Writer may never have started if no frames were received
        guard writer.status == .writing else {
            // Clean up the file if writer never completed
            if let url = videoURL {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        }

        // Finish writing
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        await writer.finishWriting()

        guard writer.status == .completed, let url = videoURL else {
            print("[CrustCapture] Writer finished with status: \(writer.status.rawValue), error: \(String(describing: writer.error))")
            return nil
        }

        // Clean up references
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        lastVideoBuffer = nil

        return RecordingSession(
            videoURL: url,
            cursorEventsURL: url.deletingPathExtension().appendingPathExtension("json"),
            startTime: recordingStartTime ?? Date(),
            duration: CMTime(seconds: finalDuration, preferredTimescale: 600),
            width: width,
            height: height,
            frameRate: frameRate
        )
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            handleVideoBuffer(sampleBuffer)
        case .audio:
            handleAudioBuffer(sampleBuffer)
        @unknown default:
            break
        }
    }

    private func handleVideoBuffer(_ buffer: CMSampleBuffer) {
        guard let writer = assetWriter, let input = videoInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)

        if firstVideoTimestamp == nil {
            firstVideoTimestamp = pts
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)
            }
        }

        guard let firstPTS = firstVideoTimestamp else { return }
        let offsetPTS = CMTimeSubtract(pts, firstPTS)

        if let offsetBuffer = createOffsetBuffer(from: buffer, newTimestamp: offsetPTS) {
            if input.isReadyForMoreMediaData {
                input.append(offsetBuffer)
            }
            lastVideoBuffer = offsetBuffer
        }
    }

    private func handleAudioBuffer(_ buffer: CMSampleBuffer) {
        guard let input = audioInput, assetWriter?.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)

        if firstAudioTimestamp == nil {
            firstAudioTimestamp = pts
        }

        guard let firstPTS = firstAudioTimestamp else { return }
        let offsetPTS = CMTimeSubtract(pts, firstPTS)

        if let offsetBuffer = createOffsetAudioBuffer(from: buffer, newTimestamp: offsetPTS) {
            if input.isReadyForMoreMediaData {
                input.append(offsetBuffer)
            }
        }
    }

    private func createOffsetBuffer(from buffer: CMSampleBuffer, newTimestamp: CMTime) -> CMSampleBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: newTimestamp,
            decodeTimeStamp: .invalid
        )

        var newBuffer: CMSampleBuffer?
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: imageBuffer, formatDescriptionOut: &formatDescription)

        guard let desc = formatDescription else { return nil }

        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newBuffer
        )

        return newBuffer
    }

    private func createOffsetAudioBuffer(from buffer: CMSampleBuffer, newTimestamp: CMTime) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: newTimestamp,
            decodeTimeStamp: .invalid
        )

        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )

        return newBuffer
    }
}
