import CoreGraphics
import CoreMedia

struct ZoomKeyframe {
    let timestamp: Double    // seconds
    let centerX: CGFloat     // 0-1 normalized
    let centerY: CGFloat     // 0-1 normalized
    let scale: CGFloat       // 1.0 = no zoom, 2.0 = 2x zoom
}

class AutoZoomAnalyzer {
    /// Analyzes cursor click events and generates smooth zoom keyframes.
    /// Stays zoomed in as long as clicks keep happening, panning between locations.
    static func generateKeyframes(
        from events: [CursorEvent],
        zoomScale: CGFloat = 2.0,
        transitionDuration: Double = 0.8
    ) -> [ZoomKeyframe] {
        let clicks = events.filter { $0.isClick }
        guard !clicks.isEmpty else { return [] }

        // Group clicks into "zoom regions" — consecutive clicks within a gap threshold
        // stay in one continuous zoom, panning between positions as needed.
        let maxGap = 4.0 // seconds — if next click is within this, stay zoomed and pan
        let holdAfter = 1.5 // seconds to hold zoom after last click in a region

        var regions: [[(timestamp: Double, x: CGFloat, y: CGFloat)]] = []
        var currentRegion: [(timestamp: Double, x: CGFloat, y: CGFloat)] = []

        for click in clicks {
            let entry = (timestamp: click.timestamp, x: click.position.x, y: click.position.y)
            if let last = currentRegion.last {
                if click.timestamp - last.timestamp <= maxGap {
                    currentRegion.append(entry)
                } else {
                    regions.append(currentRegion)
                    currentRegion = [entry]
                }
            } else {
                currentRegion = [entry]
            }
        }
        if !currentRegion.isEmpty { regions.append(currentRegion) }

        var keyframes: [ZoomKeyframe] = []

        for region in regions {
            guard let first = region.first, let last = region.last else { continue }

            // Ease in before the first click
            let zoomInStart = max(0, first.timestamp - transitionDuration)
            keyframes.append(ZoomKeyframe(
                timestamp: zoomInStart,
                centerX: first.x,
                centerY: first.y,
                scale: 1.0
            ))

            // Fully zoomed at first click
            keyframes.append(ZoomKeyframe(
                timestamp: first.timestamp,
                centerX: first.x,
                centerY: first.y,
                scale: zoomScale
            ))

            // Pan smoothly between each click position within the region
            for i in 1..<region.count {
                let prev = region[i - 1]
                let curr = region[i]
                let dist = hypot(curr.x - prev.x, curr.y - prev.y)

                // Only add a pan keyframe if the cursor moved significantly
                if dist > 0.05 {
                    // Hold at previous position until partway to the next click
                    let gap = curr.timestamp - prev.timestamp
                    let panStart = prev.timestamp + gap * 0.4
                    let panEnd = prev.timestamp + gap * 0.85

                    keyframes.append(ZoomKeyframe(
                        timestamp: panStart,
                        centerX: prev.x,
                        centerY: prev.y,
                        scale: zoomScale
                    ))
                    keyframes.append(ZoomKeyframe(
                        timestamp: panEnd,
                        centerX: curr.x,
                        centerY: curr.y,
                        scale: zoomScale
                    ))
                }
            }

            // Hold zoom after last click
            let holdEnd = last.timestamp + holdAfter
            keyframes.append(ZoomKeyframe(
                timestamp: holdEnd,
                centerX: last.x,
                centerY: last.y,
                scale: zoomScale
            ))

            // Ease out
            keyframes.append(ZoomKeyframe(
                timestamp: holdEnd + transitionDuration,
                centerX: last.x,
                centerY: last.y,
                scale: 1.0
            ))
        }

        return keyframes.sorted { $0.timestamp < $1.timestamp }
    }

    /// Interpolate zoom state at a given timestamp
    static func interpolate(keyframes: [ZoomKeyframe], at time: Double) -> (centerX: CGFloat, centerY: CGFloat, scale: CGFloat) {
        guard !keyframes.isEmpty else { return (0.5, 0.5, 1.0) }

        if time <= keyframes.first!.timestamp { return (0.5, 0.5, 1.0) }
        if time >= keyframes.last!.timestamp { return (0.5, 0.5, 1.0) }

        for i in 0..<(keyframes.count - 1) {
            let kf0 = keyframes[i]
            let kf1 = keyframes[i + 1]

            if time >= kf0.timestamp && time <= kf1.timestamp {
                let duration = kf1.timestamp - kf0.timestamp
                guard duration > 0 else {
                    return (kf1.centerX, kf1.centerY, kf1.scale)
                }

                let t = (time - kf0.timestamp) / duration
                let eased = smoothStep(CGFloat(t))

                let cx = kf0.centerX + (kf1.centerX - kf0.centerX) * eased
                let cy = kf0.centerY + (kf1.centerY - kf0.centerY) * eased
                let scale = kf0.scale + (kf1.scale - kf0.scale) * eased

                return (cx, cy, scale)
            }
        }

        return (0.5, 0.5, 1.0)
    }

    // MARK: - Private

    /// Quintic smootherstep — zero 1st and 2nd derivatives at endpoints
    /// for jerk-free transitions (no visible acceleration discontinuity).
    private static func smoothStep(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }
}
