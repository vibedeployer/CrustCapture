import SwiftUI
import AVFoundation
import CoreImage

@MainActor
class EditorViewModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var previewImage: CGImage?
    @Published var thumbnails: [CGImage] = []

    private var player: AVPlayer?
    private var displayLink: CVDisplayLink?
    private var compositor = CompositorPipeline()
    private var zoomKeyframes: [ZoomKeyframe] = []

    private var imageGenerator: AVAssetImageGenerator?
    private var project: Project?

    func loadProject(_ project: Project) {
        self.project = project
        currentTime = project.trimRange.startSeconds

        let asset = AVAsset(url: project.recording.videoURL)
        imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator?.appliesPreferredTrackTransform = true
        imageGenerator?.maximumSize = CGSize(width: 1920, height: 1080)

        // Generate zoom keyframes
        if project.effectSettings.autoZoomEnabled {
            zoomKeyframes = AutoZoomAnalyzer.generateKeyframes(
                from: project.cursorEvents,
                zoomScale: project.effectSettings.autoZoomScale
            )
        }

        // Generate initial preview
        updatePreview()

        // Generate timeline thumbnails
        generateThumbnails()
    }

    func seek(to time: Double) {
        guard let project = project else { return }
        currentTime = max(project.trimRange.startSeconds, min(time, project.trimRange.endSeconds))
        updatePreview()
    }

    func scrub(fraction: Double) {
        guard let project = project else { return }
        let start = project.trimRange.startSeconds
        let end = project.trimRange.endSeconds
        let time = start + fraction * (end - start)
        seek(to: time)
    }

    func updatePreview() {
        guard let project = project, let generator = imageGenerator else { return }

        let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
        let currentTime = self.currentTime
        let zoomKeyframes = self.zoomKeyframes
        let compositor = self.compositor

        // Capture all needed values on the main actor before detaching
        let settings = project.effectSettings
        let cursorEvents = project.cursorEvents
        let recordingWidth = CGFloat(project.recording.width)
        let recordingHeight = CGFloat(project.recording.height)

        Task.detached {
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else { return }

            let ciImage = CIImage(cgImage: cgImage)
            let padding = settings.padding

            let outputWidth = recordingWidth + padding * 2
            let outputHeight = recordingHeight + padding * 2
            let outputSize = CGSize(width: outputWidth, height: outputHeight)

            // Get cursor state
            let cursorPos = EditorViewModel.findCursorPosition(in: cursorEvents, at: currentTime)
            let clickState = EditorViewModel.findClickState(in: cursorEvents, at: currentTime)
            let zoomState = AutoZoomAnalyzer.interpolate(keyframes: zoomKeyframes, at: currentTime)

            let composited = compositor.composite(
                frame: ciImage,
                settings: settings,
                cursorPosition: cursorPos,
                isClick: clickState.isClick,
                clickIntensity: clickState.intensity,
                zoom: zoomState,
                outputSize: outputSize
            )

            if let result = compositor.renderToImage(composited) {
                await MainActor.run { [weak self] in
                    self?.previewImage = result
                }
            }
        }
    }

    private var playbackTimer: Timer?

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let project = project else { return }
        isPlaying = true

        let fps = 1.0 / 30.0 // 30fps preview playback
        playbackTimer = Timer.scheduledTimer(withTimeInterval: fps, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let project = self.project else { return }
                self.currentTime += fps
                if self.currentTime >= project.trimRange.endSeconds {
                    self.currentTime = project.trimRange.startSeconds
                    self.stopPlayback()
                }
                self.updatePreview()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func regenerateZoomKeyframes() {
        guard let project = project else { return }
        if project.effectSettings.autoZoomEnabled {
            zoomKeyframes = AutoZoomAnalyzer.generateKeyframes(
                from: project.cursorEvents,
                zoomScale: project.effectSettings.autoZoomScale
            )
        } else {
            zoomKeyframes = []
        }
        updatePreview()
    }

    private func generateThumbnails() {
        guard let project = project, let generator = imageGenerator else { return }

        let duration = project.recording.durationSeconds
        let count = 20
        let interval = duration / Double(count)

        let times = (0..<count).map { i in
            CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
        }

        Task.detached { [weak self] in
            var thumbs: [CGImage] = []
            for time in times {
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    thumbs.append(cgImage)
                }
            }
            await MainActor.run {
                self?.thumbnails = thumbs
            }
        }
    }

    private nonisolated static func findCursorPosition(in events: [CursorEvent], at time: Double) -> CGPoint? {
        var closest: CursorEvent?
        var minDiff = Double.greatestFiniteMagnitude
        for event in events {
            let diff = abs(event.timestamp - time)
            if diff < minDiff { minDiff = diff; closest = event }
            if event.timestamp > time + 0.1 { break }
        }
        if minDiff < 0.1, let e = closest { return e.position }
        return nil
    }

    private nonisolated static func findClickState(in events: [CursorEvent], at time: Double) -> (isClick: Bool, intensity: CGFloat) {
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
