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
    /// Stays zoomed in as long as clicking continues in the same area.
    static func generateKeyframes(
        from events: [CursorEvent],
        zoomScale: CGFloat = 2.0,
        holdDuration: Double = 2.5,
        transitionDuration: Double = 0.5
    ) -> [ZoomKeyframe] {
        let clicks = events.filter { $0.isClick }
        guard !clicks.isEmpty else { return [] }

        // Cluster clicks with generous thresholds — keep rapid clicks in the same cluster
        let clusters = clusterClicks(clicks, timeThreshold: 2.0, distanceThreshold: 0.25)

        var keyframes: [ZoomKeyframe] = []

        for cluster in clusters {
            let centroid = clusterCentroid(cluster)
            let firstClick = cluster.first!.timestamp
            let lastClick = cluster.last!.timestamp

            // Ease in: start zooming before the first click
            let zoomInStart = max(0, firstClick - transitionDuration)

            // At rest just before transition
            keyframes.append(ZoomKeyframe(
                timestamp: zoomInStart,
                centerX: centroid.x,
                centerY: centroid.y,
                scale: 1.0
            ))

            // Fully zoomed at first click
            keyframes.append(ZoomKeyframe(
                timestamp: firstClick,
                centerX: centroid.x,
                centerY: centroid.y,
                scale: zoomScale
            ))

            // Stay zoomed through the entire cluster + hold duration after last click
            let holdEnd = lastClick + holdDuration

            keyframes.append(ZoomKeyframe(
                timestamp: holdEnd,
                centerX: centroid.x,
                centerY: centroid.y,
                scale: zoomScale
            ))

            // Ease out
            keyframes.append(ZoomKeyframe(
                timestamp: holdEnd + transitionDuration,
                centerX: centroid.x,
                centerY: centroid.y,
                scale: 1.0
            ))
        }

        return mergeOverlappingZooms(keyframes, transitionDuration: transitionDuration)
    }

    /// Interpolate zoom state at a given timestamp using spring-like easing
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

    private static func smoothStep(_ t: CGFloat) -> CGFloat {
        let t2 = t * t
        return t2 * (3 - 2 * t)
    }

    private static func clusterClicks(_ clicks: [CursorEvent], timeThreshold: Double, distanceThreshold: CGFloat) -> [[CursorEvent]] {
        var clusters: [[CursorEvent]] = []
        var currentCluster: [CursorEvent] = []

        for click in clicks {
            if let last = currentCluster.last {
                let timeDiff = click.timestamp - last.timestamp
                let dist = hypot(click.position.x - last.position.x, click.position.y - last.position.y)

                if timeDiff < timeThreshold && dist < distanceThreshold {
                    currentCluster.append(click)
                } else {
                    if !currentCluster.isEmpty { clusters.append(currentCluster) }
                    currentCluster = [click]
                }
            } else {
                currentCluster = [click]
            }
        }

        if !currentCluster.isEmpty { clusters.append(currentCluster) }
        return clusters
    }

    private static func clusterCentroid(_ cluster: [CursorEvent]) -> CGPoint {
        let sumX = cluster.reduce(0.0) { $0 + $1.position.x }
        let sumY = cluster.reduce(0.0) { $0 + $1.position.y }
        let count = CGFloat(cluster.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    /// Merge overlapping zoom regions — if one zoom-out overlaps the next zoom-in,
    /// keep zoomed and smoothly pan to the new center instead.
    private static func mergeOverlappingZooms(_ keyframes: [ZoomKeyframe], transitionDuration: Double) -> [ZoomKeyframe] {
        let sorted = keyframes.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 4 else { return sorted }

        var result: [ZoomKeyframe] = []
        var i = 0

        while i < sorted.count {
            let kf = sorted[i]

            // Check if this is a zoom-out (scale going to 1.0) that overlaps the next zoom-in
            if kf.scale == 1.0 && i + 1 < sorted.count {
                let next = sorted[i + 1]
                // If the next keyframe starts zooming before this zoom-out completes
                if next.timestamp <= kf.timestamp + transitionDuration && next.scale == 1.0 {
                    // Skip both the zoom-out and the next zoom-in — stay zoomed
                    // Add a pan keyframe to the new center instead
                    if i + 2 < sorted.count {
                        let zoomedKf = sorted[i + 2]
                        result.append(ZoomKeyframe(
                            timestamp: kf.timestamp,
                            centerX: zoomedKf.centerX,
                            centerY: zoomedKf.centerY,
                            scale: zoomedKf.scale
                        ))
                        i += 2 // Skip the zoom-out and zoom-in pair
                        continue
                    }
                }
            }

            result.append(kf)
            i += 1
        }

        return result
    }
}
