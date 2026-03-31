import AppKit
import CoreMedia

class CursorTracker {
    private var events: [CursorEvent] = []
    private var startTime: Date?
    private var moveMonitor: Any?
    private var clickMonitor: Any?
    private var trackingTimer: Timer?
    private let captureFrame: CGRect // the frame of the captured area in screen coordinates

    init(captureFrame: CGRect) {
        self.captureFrame = captureFrame
    }

    func start() {
        events = []
        startTime = Date()

        // Track cursor position at regular intervals
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.recordCurrentPosition(isClick: false)
        }

        // Track clicks
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.recordCurrentPosition(isClick: true)
        }
    }

    func stop() -> [CursorEvent] {
        trackingTimer?.invalidate()
        trackingTimer = nil

        if let monitor = moveMonitor {
            NSEvent.removeMonitor(monitor)
            moveMonitor = nil
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        return events
    }

    private func recordCurrentPosition(isClick: Bool) {
        guard let startTime = startTime else { return }

        let mouseLocation = NSEvent.mouseLocation
        // Convert screen coordinates to capture-relative normalized coordinates (0-1)
        let relativeX = (mouseLocation.x - captureFrame.origin.x) / captureFrame.width
        // Flip Y because screen coordinates are bottom-up but video is top-down
        let relativeY = 1.0 - (mouseLocation.y - captureFrame.origin.y) / captureFrame.height

        // Only record if cursor is within captured area
        guard relativeX >= 0, relativeX <= 1, relativeY >= 0, relativeY <= 1 else { return }

        let timestamp = Date().timeIntervalSince(startTime)
        let event = CursorEvent(
            position: CGPoint(x: relativeX, y: relativeY),
            isClick: isClick,
            timestamp: timestamp
        )
        events.append(event)
    }

    func saveToDisk(url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(events) {
            try? data.write(to: url)
        }
    }
}
