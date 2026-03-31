import SwiftUI
import ScreenCaptureKit

enum AppMode: Equatable {
    case setup
    case recording
    case editing
    case exporting
}

@MainActor
class AppState: ObservableObject {
    @Published var mode: AppMode = .setup
    @Published var currentProject: Project?

    func startRecording() {
        mode = .recording
    }

    func stopRecording(session: RecordingSession, cursorEvents: [CursorEvent]) {
        let settings = EffectSettings()
        currentProject = Project(
            recording: session,
            cursorEvents: cursorEvents,
            effectSettings: settings
        )
        mode = .editing
    }

    func backToSetup() {
        currentProject = nil
        mode = .setup
    }

    func startExport() {
        mode = .exporting
    }

    func finishExport() {
        mode = .editing
    }
}
