import CoreMedia
import CoreGraphics

struct CursorEvent: Codable {
    let position: CGPoint
    let isClick: Bool
    let timestamp: Double // seconds from recording start

    var cmTime: CMTime {
        CMTime(seconds: timestamp, preferredTimescale: 600)
    }
}
