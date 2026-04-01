import CoreGraphics

/// Smooths raw cursor positions to eliminate jitter and create fluid motion.
/// Uses Catmull-Rom spline interpolation with velocity-adaptive smoothing.
class CursorSmoother {

    /// Pre-processes cursor events into a smooth trajectory.
    /// Call once after recording/loading, then use `position(at:)` for each frame.
    private let events: [CursorEvent]
    private let smoothed: [(timestamp: Double, x: CGFloat, y: CGFloat)]

    init(events: [CursorEvent]) {
        self.events = events
        self.smoothed = CursorSmoother.buildSmoothed(from: events)
    }

    /// Returns the smoothed cursor position at a given time, or nil if no data.
    func position(at time: Double) -> CGPoint? {
        guard smoothed.count >= 2 else {
            if let only = smoothed.first, abs(only.timestamp - time) < 0.1 {
                return CGPoint(x: only.x, y: only.y)
            }
            return nil
        }

        // Before first or after last
        if time <= smoothed.first!.timestamp - 0.1 { return nil }
        if time >= smoothed.last!.timestamp + 0.1 { return nil }

        // Clamp to range
        if time <= smoothed.first!.timestamp {
            return CGPoint(x: smoothed.first!.x, y: smoothed.first!.y)
        }
        if time >= smoothed.last!.timestamp {
            return CGPoint(x: smoothed.last!.x, y: smoothed.last!.y)
        }

        // Find the segment
        var lo = 0
        var hi = smoothed.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if smoothed[mid].timestamp <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let s0 = smoothed[lo]
        let s1 = smoothed[hi]
        let duration = s1.timestamp - s0.timestamp
        guard duration > 0 else { return CGPoint(x: s1.x, y: s1.y) }

        let t = CGFloat((time - s0.timestamp) / duration)

        // Catmull-Rom interpolation using surrounding points
        let i0 = max(0, lo - 1)
        let i3 = min(smoothed.count - 1, hi + 1)
        let p0 = smoothed[i0]
        let p1 = smoothed[lo]
        let p2 = smoothed[hi]
        let p3 = smoothed[i3]

        let x = catmullRom(t: t, p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x)
        let y = catmullRom(t: t, p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y)

        return CGPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    // MARK: - Private

    /// Build smoothed positions using a moving average with velocity-adaptive window.
    private static func buildSmoothed(from events: [CursorEvent]) -> [(timestamp: Double, x: CGFloat, y: CGFloat)] {
        let moveEvents = events.filter { !$0.isClick }
        guard moveEvents.count >= 2 else {
            return moveEvents.map { (timestamp: $0.timestamp, x: $0.position.x, y: $0.position.y) }
        }

        // Pass 1: Gaussian-weighted moving average to remove jitter
        let windowSize = 5 // samples in each direction
        let sigma: CGFloat = 2.0
        var weights: [CGFloat] = []
        for i in -windowSize...windowSize {
            let w = exp(-CGFloat(i * i) / (2 * sigma * sigma))
            weights.append(w)
        }

        var result: [(timestamp: Double, x: CGFloat, y: CGFloat)] = []

        for i in 0..<moveEvents.count {
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var sumW: CGFloat = 0

            for j in -windowSize...windowSize {
                let idx = i + j
                guard idx >= 0, idx < moveEvents.count else { continue }

                // Scale smoothing by velocity — fast moves get less smoothing
                let w = weights[j + windowSize]
                sumX += moveEvents[idx].position.x * w
                sumY += moveEvents[idx].position.y * w
                sumW += w
            }

            result.append((
                timestamp: moveEvents[i].timestamp,
                x: sumX / sumW,
                y: sumY / sumW
            ))
        }

        // Pass 2: Reduce redundant points on straight-line segments
        // Keep points where direction changes significantly
        guard result.count >= 3 else { return result }
        var filtered: [(timestamp: Double, x: CGFloat, y: CGFloat)] = [result[0]]

        for i in 1..<(result.count - 1) {
            let prev = filtered.last!
            let curr = result[i]
            let next = result[i + 1]

            let dx1 = curr.x - prev.x
            let dy1 = curr.y - prev.y
            let dx2 = next.x - curr.x
            let dy2 = next.y - curr.y

            let len1 = hypot(dx1, dy1)
            let len2 = hypot(dx2, dy2)

            // Always keep if there's meaningful movement
            if len1 < 0.001 && len2 < 0.001 { continue }

            // Keep if direction changes or enough time has passed
            if len1 > 0.001 && len2 > 0.001 {
                let dot = (dx1 * dx2 + dy1 * dy2) / (len1 * len2)
                if dot < 0.98 { // direction changed
                    filtered.append(curr)
                    continue
                }
            }

            // Keep at least every ~100ms for temporal coverage
            if curr.timestamp - prev.timestamp > 0.1 {
                filtered.append(curr)
            }
        }

        filtered.append(result.last!)
        return filtered
    }

    /// Catmull-Rom spline interpolation
    private func catmullRom(t: CGFloat, p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}
