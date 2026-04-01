import AVFoundation
import CoreImage
import AppKit

private func exportLog(_ message: String) {
    #if DEBUG
    print("[Export] \(message)")
    #endif
}

enum ExportQuality: String, CaseIterable {
    case optimized = "Optimized for sharing"
    case high = "High quality"
    case maximum = "Maximum quality"

    var videoBitRate: Int {
        switch self {
        case .optimized: return 8_000_000
        case .high: return 20_000_000
        case .maximum: return 50_000_000
        }
    }
}

enum ExportCodec: String, CaseIterable {
    case h264 = "H.264"
    case hevc = "HEVC (H.265)"

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

class ExportEngine: ObservableObject {
    @MainActor @Published var progress: Double = 0
    @MainActor @Published var isExporting = false
    @MainActor @Published var error: String?
    @MainActor @Published var exportedURL: URL?

    private var cancelled = false

    func export(
        project: Project,
        outputURL: URL,
        codec: ExportCodec = .hevc,
        quality: ExportQuality = .high,
        maxWidth: Int = 1920
    ) {
        cancelled = false

        // Capture everything from the project on the main thread
        let settings = project.effectSettings
        let cursorEvents = project.cursorEvents
        let videoURL = project.recording.videoURL
        let recordingWidth = project.recording.width
        let recordingHeight = project.recording.height
        let trimStartSeconds = project.trimRange.startSeconds
        let trimEndSeconds = project.trimRange.endSeconds
        let totalDuration = project.trimmedDuration

        DispatchQueue.main.async {
            self.isExporting = true
            self.progress = 0
            self.error = nil
            self.exportedURL = nil
        }

        let exportMaxWidth = maxWidth

        // Do setup on a background queue, then use requestMediaDataWhenReady
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.performExport(
                outputURL: outputURL,
                codec: codec,
                quality: quality,
                maxWidth: exportMaxWidth,
                settings: settings,
                cursorEvents: cursorEvents,
                videoURL: videoURL,
                recordingWidth: recordingWidth,
                recordingHeight: recordingHeight,
                trimStartSeconds: trimStartSeconds,
                trimEndSeconds: trimEndSeconds,
                totalDuration: totalDuration
            )
        }
    }

    private func performExport(
        outputURL: URL,
        codec: ExportCodec,
        quality: ExportQuality,
        maxWidth: Int,
        settings: EffectSettings,
        cursorEvents: [CursorEvent],
        videoURL: URL,
        recordingWidth: Int,
        recordingHeight: Int,
        trimStartSeconds: Double,
        trimEndSeconds: Double,
        totalDuration: Double
    ) {
        exportLog("[Export] Starting export to \(outputURL.lastPathComponent)")

        let compositor = CompositorPipeline()

        // Smoothed cursor trajectory
        let cursorSmoother = CursorSmoother(events: cursorEvents)

        // Zoom keyframes
        let zoomKeyframes: [ZoomKeyframe]
        if settings.autoZoomEnabled {
            zoomKeyframes = AutoZoomAnalyzer.generateKeyframes(
                from: cursorEvents, zoomScale: settings.autoZoomScale
            )
        } else {
            zoomKeyframes = []
        }

        // Set up reader
        let asset = AVAsset(url: videoURL)
        guard let reader = try? AVAssetReader(asset: asset) else {
            finishWithError("Failed to create asset reader"); return
        }

        // Load tracks synchronously
        let semaphore = DispatchSemaphore(value: 0)
        var videoTrack: AVAssetTrack?
        var audioTrack: AVAssetTrack?
        Task {
            videoTrack = try? await asset.loadTracks(withMediaType: .video).first
            audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
            semaphore.signal()
        }
        semaphore.wait()

        guard let vTrack = videoTrack else {
            finishWithError("No video track found"); return
        }

        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: vTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(videoReaderOutput)

        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let aTrack = audioTrack {
            let aOutput = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2
            ])
            reader.add(aOutput)
            audioReaderOutput = aOutput
        }

        // Trim range
        let trimStart = CMTime(seconds: trimStartSeconds, preferredTimescale: 600)
        let trimEnd = CMTime(seconds: trimEndSeconds, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: trimStart, end: trimEnd)

        // Output dimensions
        let rawSize = settings.outputSize(recordingWidth: CGFloat(recordingWidth), recordingHeight: CGFloat(recordingHeight))
        let capWidth = maxWidth > 0 ? CGFloat(maxWidth) : rawSize.width
        let scale = rawSize.width > capWidth ? capWidth / rawSize.width : 1.0
        let finalWidth = Int(rawSize.width * scale) & ~1
        let finalHeight = Int(rawSize.height * scale) & ~1
        let outputSize = CGSize(width: finalWidth, height: finalHeight)

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            finishWithError("Failed to create asset writer"); return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: finalWidth,
            AVVideoHeightKey: finalHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.videoBitRate
            ]
        ]

        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerVideoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: finalWidth,
                kCVPixelBufferHeightKey as String: finalHeight
            ]
        )
        writer.add(writerVideoInput)

        var writerAudioInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256000
            ])
            aInput.expectsMediaDataInRealTime = false
            writer.add(aInput)
            writerAudioInput = aInput
        }

        // Start
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        exportLog("[Export] Reader: \(reader.status.rawValue), Writer: \(writer.status.rawValue), Size: \(outputSize)")

        // Use DispatchGroup to coordinate video + audio completion
        let group = DispatchGroup()

        // --- Video track ---
        let videoQueue = DispatchQueue(label: "com.crustcapture.export.video")
        group.enter()
        var frameCount = 0
        var videoDone = false

        writerVideoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self = self, !videoDone, reader.status == .reading else { return }

            while writerVideoInput.isReadyForMoreMediaData && !videoDone {
                if self.cancelled || reader.status != .reading {
                    guard !videoDone else { return }
                    videoDone = true
                    writerVideoInput.markAsFinished()
                    group.leave()
                    return
                }

                guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                    guard !videoDone else { return }
                    exportLog("[Export] Video done. \(frameCount) frames.")
                    videoDone = true
                    writerVideoInput.markAsFinished()
                    group.leave()
                    return
                }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let timeSeconds = CMTimeGetSeconds(pts) + trimStartSeconds

                let cursorPos = cursorSmoother.position(at: timeSeconds)
                    ?? ExportEngine.findCursorPosition(in: cursorEvents, at: timeSeconds)
                let clickState = ExportEngine.findClickState(in: cursorEvents, at: timeSeconds)
                let zoomState = AutoZoomAnalyzer.interpolate(keyframes: zoomKeyframes, at: timeSeconds)

                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)

                let composited = compositor.composite(
                    frame: ciImage,
                    settings: settings,
                    cursorPosition: cursorPos,
                    isClick: clickState.isClick,
                    clickIntensity: clickState.intensity,
                    zoom: zoomState,
                    outputSize: outputSize
                )

                guard let pool = pixelBufferAdaptor.pixelBufferPool else { continue }
                var outputBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
                guard let buffer = outputBuffer else { continue }

                compositor.render(composited, to: buffer)

                let outputPTS = CMTimeSubtract(pts, trimStart)
                pixelBufferAdaptor.append(buffer, withPresentationTime: outputPTS)
                frameCount += 1

                if frameCount <= 3 || frameCount % 50 == 0 {
                    exportLog("[Export] Frame \(frameCount), pts: \(CMTimeGetSeconds(outputPTS))s")
                }

                if frameCount % 5 == 0 {
                    let p = min(1.0, max(0.0, CMTimeGetSeconds(pts) / totalDuration))
                    DispatchQueue.main.async { self.progress = p }
                }
            }
            // isReadyForMoreMediaData is false — just return.
            // The framework will call this block again when ready.
        }

        // --- Audio track ---
        if let audioOutput = audioReaderOutput, let audioInput = writerAudioInput {
            let audioQueue = DispatchQueue(label: "com.crustcapture.export.audio")
            group.enter()
            var audioDone = false

            audioInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                guard let self = self, !audioDone, reader.status == .reading else { return }

                while audioInput.isReadyForMoreMediaData && !audioDone {
                    if self.cancelled || reader.status != .reading {
                        guard !audioDone else { return }
                        audioDone = true
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }

                    guard let audioBuffer = audioOutput.copyNextSampleBuffer() else {
                        guard !audioDone else { return }
                        exportLog("[Export] Audio done.")
                        audioDone = true
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }

                    // Offset audio timestamps to start at zero (matching video)
                    let audioPTS = CMSampleBufferGetPresentationTimeStamp(audioBuffer)
                    let offsetPTS = CMTimeSubtract(audioPTS, trimStart)

                    var timingInfo = CMSampleTimingInfo(
                        duration: CMSampleBufferGetDuration(audioBuffer),
                        presentationTimeStamp: offsetPTS,
                        decodeTimeStamp: .invalid
                    )
                    var offsetBuffer: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(
                        allocator: nil,
                        sampleBuffer: audioBuffer,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: &timingInfo,
                        sampleBufferOut: &offsetBuffer
                    )

                    if let buffer = offsetBuffer {
                        audioInput.append(buffer)
                    } else {
                        audioInput.append(audioBuffer)
                    }
                }
            }
        }

        // --- Finish when both tracks are done ---
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            exportLog("[Export] Both tracks done. Finishing writing...")

            writer.finishWriting {
                exportLog("[Export] Writer finished. Status: \(writer.status.rawValue), error: \(String(describing: writer.error))")

                DispatchQueue.main.async {
                    if writer.status == .completed {
                        self.progress = 1.0
                        self.exportedURL = outputURL
                    } else {
                        self.error = writer.error?.localizedDescription ?? "Export failed"
                    }
                    self.isExporting = false
                }
            }
        }
    }

    func cancel() {
        cancelled = true
    }

    private func finishWithError(_ message: String) {
        exportLog("[Export] Error: \(message)")
        DispatchQueue.main.async {
            self.error = message
            self.isExporting = false
        }
    }

    // MARK: - Private

    private static func findCursorPosition(in events: [CursorEvent], at time: Double) -> CGPoint? {
        var closest: CursorEvent?
        var minDiff = Double.greatestFiniteMagnitude
        for event in events {
            let diff = abs(event.timestamp - time)
            if diff < minDiff { minDiff = diff; closest = event }
            if event.timestamp > time + 0.1 { break }
        }
        if minDiff < 0.1, let event = closest { return event.position }
        return nil
    }

    private static func findClickState(in events: [CursorEvent], at time: Double) -> (isClick: Bool, intensity: CGFloat) {
        for event in events where event.isClick {
            let diff = time - event.timestamp
            if diff >= 0 && diff < 0.3 {
                let intensity: CGFloat = diff < 0.05
                    ? CGFloat(diff / 0.05)
                    : CGFloat(1.0 - (diff - 0.05) / 0.25)
                return (true, max(0, intensity))
            }
        }
        return (false, 0)
    }
}
