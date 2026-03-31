import SwiftUI
import ScreenCaptureKit
import AppKit

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var selectedSource: CaptureSource?
    @Published var isCountingDown = false
    @Published var countdownValue = 3
    @Published var includeMicrophone = false
    @Published var frameRate = 60
    @Published var isLoadingSources = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var screenCaptureGranted = false
    @Published var hideWindowDuringRecording = true

    let screenCaptureService = ScreenCaptureService()
    let permissionsService = PermissionsService()
    let recordingEngine = RecordingEngine()

    private var cursorTracker: CursorTracker?
    private var durationTimer: Timer?

    var isRecording: Bool {
        recordingDuration > 0
    }

    var formattedDuration: String {
        let total = Int(recordingDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var pollTask: Task<Void, Never>?

    func setup() async {
        await checkSources()
        // If no sources yet, keep polling every 2 seconds until they appear
        if screenCaptureService.availableSources.isEmpty {
            startPolling()
        }
    }

    private func checkSources() async {
        do {
            try await screenCaptureService.refreshSources()
            let hasSources = !screenCaptureService.availableSources.isEmpty
            screenCaptureGranted = hasSources
            if hasSources { isLoadingSources = false }
        } catch {
            screenCaptureGranted = false
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled && screenCaptureService.availableSources.isEmpty {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await checkSources()
            }
            pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshSources() async {
        try? await screenCaptureService.refreshSources()
    }

    func startRecording(appState: AppState) async {
        guard let source = selectedSource else { return }

        // Countdown with sound
        isCountingDown = true
        for i in (1...3).reversed() {
            countdownValue = i
            NSSound(named: "Tink")?.play()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        isCountingDown = false

        // Hide window if option is on
        if hideWindowDuringRecording {
            NSApp.windows.first?.miniaturize(nil)
        }

        // Small delay after minimizing so the window animation completes
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Set up capture
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let content = content else { return }

        let filter = screenCaptureService.createFilter(for: source, content: content)
        let config = screenCaptureService.createConfiguration(for: source, frameRate: frameRate)

        let urls = RecordingSession.newRecordingURLs()

        // Start cursor tracking
        cursorTracker = CursorTracker(captureFrame: source.frame)
        cursorTracker?.start()

        // Start recording
        do {
            try await recordingEngine.startRecording(
                filter: filter,
                configuration: config,
                videoURL: urls.video
            )
            recordingDuration = 0
            let startTime = Date()
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingDuration = Date().timeIntervalSince(startTime)
                }
            }
            appState.startRecording()
        } catch {
            print("Failed to start recording: \(error)")
            cursorTracker?.stop()
            cursorTracker = nil
            // Show window again on failure
            NSApp.windows.first?.deminiaturize(nil)
        }
    }

    func stopRecording(appState: AppState) async {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0

        let cursorEvents = cursorTracker?.stop() ?? []
        cursorTracker = nil

        if let session = await recordingEngine.stopRecording() {
            // Save cursor events
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(cursorEvents) {
                try? data.write(to: session.cursorEventsURL)
            }

            // Show window again
            NSApp.windows.first?.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)

            appState.stopRecording(session: session, cursorEvents: cursorEvents)
        }
    }
}
