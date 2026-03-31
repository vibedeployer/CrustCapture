import Foundation
import CoreMedia

struct RecordingSession {
    let videoURL: URL
    let cursorEventsURL: URL
    let startTime: Date
    let duration: CMTime
    let width: Int
    let height: Int
    let frameRate: Int

    var durationSeconds: Double {
        CMTimeGetSeconds(duration)
    }

    static func outputDirectory() -> URL {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CrustCapture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newRecordingURLs() -> (video: URL, cursors: URL) {
        let dir = outputDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let video = dir.appendingPathComponent("recording-\(timestamp).mov")
        let cursors = dir.appendingPathComponent("recording-\(timestamp)-cursors.json")
        return (video, cursors)
    }
}
