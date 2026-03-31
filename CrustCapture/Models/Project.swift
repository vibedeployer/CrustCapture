import Foundation
import CoreMedia

struct TrimRange: Equatable {
    var startSeconds: Double = 0
    var endSeconds: Double = 0 // 0 means end of recording
}

class Project: ObservableObject {
    let recording: RecordingSession
    let cursorEvents: [CursorEvent]
    @Published var effectSettings: EffectSettings
    @Published var trimRange: TrimRange

    private var undoStack: [(EffectSettings, TrimRange)] = []
    private var redoStack: [(EffectSettings, TrimRange)] = []

    init(recording: RecordingSession, cursorEvents: [CursorEvent], effectSettings: EffectSettings) {
        self.recording = recording
        self.cursorEvents = cursorEvents
        self.effectSettings = effectSettings
        self.trimRange = TrimRange(startSeconds: 0, endSeconds: recording.durationSeconds)
    }

    var trimmedDuration: Double {
        trimRange.endSeconds - trimRange.startSeconds
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func saveState() {
        undoStack.append((effectSettings, trimRange))
        redoStack.removeAll()
        // Keep undo stack manageable
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append((effectSettings, trimRange))
        effectSettings = previous.0
        trimRange = previous.1
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((effectSettings, trimRange))
        effectSettings = next.0
        trimRange = next.1
    }
}
