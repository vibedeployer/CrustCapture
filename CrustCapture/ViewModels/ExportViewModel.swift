import SwiftUI
import UniformTypeIdentifiers
import Combine
import ImageIO
import AVFoundation

enum ExportResolution: String, CaseIterable {
    case r1080 = "1080p"
    case r1440 = "1440p"
    case original = "Original"

    var maxWidth: Int {
        switch self {
        case .r1080: return 1920
        case .r1440: return 2560
        case .original: return 0 // no cap
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case mp4 = "MP4"
    case gif = "GIF"
}

@MainActor
class ExportViewModel: ObservableObject {
    @Published var codec: ExportCodec = .hevc
    @Published var quality: ExportQuality = .high
    @Published var resolution: ExportResolution = .r1080
    @Published var format: ExportFormat = .mp4
    @Published var isExporting = false
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var exportedURL: URL?
    @Published var openWhenDone = false

    let exportEngine = ExportEngine()
    private var observer: AnyCancellable?

    init() {
        observer = exportEngine.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isExporting = self.exportEngine.isExporting
                self.progress = self.exportEngine.progress
                self.error = self.exportEngine.error
                if let url = self.exportEngine.exportedURL {
                    self.exportedURL = url
                    if self.openWhenDone {
                        self.revealInFinder(url: url)
                    }
                }
            }
        }
    }

    func export(project: Project) {
        let isGif = format == .gif
        let panel = NSSavePanel()
        panel.allowedContentTypes = isGif ? [.gif] : [.mpeg4Movie]
        panel.nameFieldStringValue = isGif ? "CrustCapture Export.gif" : "CrustCapture Export.mp4"
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }

            if isGif {
                self.exportGIF(project: project, outputURL: url)
            } else {
                self.exportEngine.export(
                    project: project,
                    outputURL: url,
                    codec: self.codec,
                    quality: self.quality,
                    maxWidth: self.resolution.maxWidth
                )
            }
        }
    }

    private func exportGIF(project: Project, outputURL: URL) {
        isExporting = true
        progress = 0
        error = nil

        let settings = project.effectSettings
        let cursorEvents = project.cursorEvents
        let maxWidth = resolution.maxWidth > 0 ? resolution.maxWidth : 640

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let asset = AVAsset(url: project.recording.videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)

            let duration = project.trimmedDuration
            let fps = 10.0
            let frameCount = Int(duration * fps)
            let trimStart = project.trimRange.startSeconds

            // Create GIF destination
            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                "com.compuserve.gif" as CFString,
                frameCount,
                nil
            ) else {
                DispatchQueue.main.async { self.error = "Failed to create GIF"; self.isExporting = false }
                return
            }

            let gifProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: 0
                ]
            ]
            CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

            let frameDelay = 1.0 / fps
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: frameDelay
                ]
            ]

            for i in 0..<frameCount {
                let time = trimStart + Double(i) / fps
                let cmTime = CMTime(seconds: time, preferredTimescale: 600)

                guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else { continue }
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)

                if i % 5 == 0 {
                    let p = Double(i) / Double(frameCount)
                    DispatchQueue.main.async { self.progress = p }
                }
            }

            let success = CGImageDestinationFinalize(destination)

            DispatchQueue.main.async {
                if success {
                    self.progress = 1.0
                    self.exportedURL = outputURL
                } else {
                    self.error = "Failed to finalize GIF"
                }
                self.isExporting = false
            }
        }
    }

    func cancel() {
        exportEngine.cancel()
    }

    func revealInFinder(url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
}
