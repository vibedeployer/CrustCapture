import ScreenCaptureKit
import AppKit

struct CaptureSource: Identifiable, Hashable {
    let id: String
    let title: String
    let isDisplay: Bool
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    let window: SCWindow?
    let display: SCDisplay?
    let windowID: CGWindowID?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CaptureSource, rhs: CaptureSource) -> Bool {
        lhs.id == rhs.id
    }

    func captureThumbnail() -> NSImage? {
        if isDisplay, let displayID = displayID {
            // Capture entire display
            if let cgImage = CGDisplayCreateImage(displayID) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        } else if let windowID = windowID {
            // Capture specific window
            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return nil
    }
}

@MainActor
class ScreenCaptureService: ObservableObject {
    @Published var availableSources: [CaptureSource] = []

    func refreshSources() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        var sources: [CaptureSource] = []

        // Add displays
        for display in content.displays {
            sources.append(CaptureSource(
                id: "display-\(display.displayID)",
                title: "Display \(display.displayID) (\(display.width)×\(display.height))",
                isDisplay: true,
                frame: display.frame,
                displayID: display.displayID,
                window: nil,
                display: display,
                windowID: nil
            ))
        }

        // Add windows (filter out tiny or system windows)
        for window in content.windows {
            guard let app = window.owningApplication,
                  !app.applicationName.isEmpty,
                  window.frame.width > 100,
                  window.frame.height > 100,
                  window.isOnScreen else { continue }

            let title = window.title ?? app.applicationName
            sources.append(CaptureSource(
                id: "window-\(window.windowID)",
                title: "\(app.applicationName) — \(title)",
                isDisplay: false,
                frame: window.frame,
                displayID: nil,
                window: window,
                display: nil,
                windowID: window.windowID
            ))
        }

        availableSources = sources
    }

    func createFilter(for source: CaptureSource, content: SCShareableContent) -> SCContentFilter {
        if let display = source.display {
            return SCContentFilter(display: display, excludingWindows: [])
        } else if let window = source.window {
            return SCContentFilter(desktopIndependentWindow: window)
        }
        fatalError("CaptureSource has neither display nor window")
    }

    func createConfiguration(for source: CaptureSource, frameRate: Int = 60) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()

        let scaleFactor: CGFloat
        if let displayID = source.displayID {
            scaleFactor = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
            })?.backingScaleFactor ?? 2.0
        } else {
            scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        }

        config.width = Int(source.frame.width * scaleFactor)
        config.height = Int(source.frame.height * scaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        // System audio
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        return config
    }
}
