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
    /// Creates a zoom-in before each click cluster and zoom-out afterward.
    static func generateKeyframes(
        from events: [CursorEvent],
        zoomScale: CGFloat = 2.0,
        holdDuration: Double = 1.5,
        transitionDuration: Double = 0.4
    ) -> [ZoomKeyframe] {
        let clicks = events.filter { $0.isClick }
        guard !clicks.isEmpty else { return [] }

        // Cluster clicks that are close in time and space
        let clusters = clusterClicks(clicks, timeThreshold: 0.8, distanceThreshold: 0.15)

        var keyframes: [ZoomKeyframe] = []

        for cluster in clusters {
            let centroid = clusterCentroid(cluster)
            let clusterTime = cluster.first!.timestamp

            // Ease in: start zooming before the click
            let zoomInStart = max(0, clusterTime - transitionDuration)

            // At rest (no zoom) just before transition
            keyframes.append(ZoomKeyframe(
                timestamp: zoomInStart,
                centerX: centroid.x,
                centerY: centroid.y,
                scale: 1.0
            ))

            // Fully zoomed at click time
            keyframes.append(ZoomKeyframe(
                timestamp: clusterTime,
                centerX: centroid.x,
                centerY: centroid.y,
                scale: zoomScale
            ))

            // Hold zoom
            let holdEnd = clusterTime + holdDuration

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

        // Remove overlapping zoom regions (later cluster wins)
        return resolveOverlaps(keyframes)
    }

    /// Interpolate zoom state at a given timestamp using spring-like easing
    static func interpolate(keyframes: [ZoomKeyframe], at time: Double) -> (centerX: CGFloat, centerY: CGFloat, scale: CGFloat) {
        guard !keyframes.isEmpty else { return (0.5, 0.5, 1.0) }

        // Before first keyframe
        if time <= keyframes.first!.timestamp {
            return (0.5, 0.5, 1.0)
        }

        // After last keyframe
        if time >= keyframes.last!.timestamp {
            return (0.5, 0.5, 1.0)
        }

        // Find surrounding keyframes
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
        // Critically damped spring-like easing
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
                    if !currentCluster.isEmpty {
                        clusters.append(currentCluster)
                    }
                    currentCluster = [click]
                }
            } else {
                currentCluster = [click]
            }
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }

    private static func clusterCentroid(_ cluster: [CursorEvent]) -> CGPoint {
        let sumX = cluster.reduce(0.0) { $0 + $1.position.x }
        let sumY = cluster.reduce(0.0) { $0 + $1.position.y }
        let count = CGFloat(cluster.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private static func resolveOverlaps(_ keyframes: [ZoomKeyframe]) -> [ZoomKeyframe] {
        // Simple approach: sort by time and remove any keyframes that overlap with previous zoom-out
        let sorted = keyframes.sorted { $0.timestamp < $1.timestamp }

        var result: [ZoomKeyframe] = []
        var lastEndTime: Double = -1

        for kf in sorted {
            if kf.timestamp >= lastEndTime || kf.scale != 1.0 {
                result.append(kf)
                if kf.scale == 1.0 && kf.timestamp > lastEndTime {
                    lastEndTime = kf.timestamp
                }
            }
        }

        return result
    }
}
