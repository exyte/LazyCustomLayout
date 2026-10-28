import Foundation

/// Estimates the current drag velocity from recent position samples using a
/// recency-weighted least-squares line fit, in the spirit of Compose's
/// `VelocityTracker`.
///
/// Only samples from the last `historyDuration` are considered, and older
/// samples within that window are weighted less than newer ones. That means a
/// pause mid-drag (the finger stops moving right before lifting) is reflected
/// immediately in the estimate, instead of being smoothed out by stale,
/// fast-moving samples from earlier in the gesture.
public struct VelocityTracker {

    public struct Sample {
        /// Seconds, monotonically increasing.
        public var time: Double
        /// Points.
        public var position: Double

        public init(time: Double, position: Double) {
            self.time = time
            self.position = position
        }
    }

    public var historyDuration: Double

    private var samples: [Sample] = []

    public init(historyDuration: Double = 0.1) {
        self.historyDuration = historyDuration
    }

    /// Records a new position sample and discards samples older than `historyDuration`.
    public mutating func addSample(time: Double, position: Double) {
        samples.append(Sample(time: time, position: position))

        let cutoff = time - historyDuration
        samples.removeAll { $0.time < cutoff }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// Samples currently within `historyDuration`. Below 2, `velocity` can't
    /// fit a line and reports `0` regardless of how fast the motion actually
    /// was — callers that have their own velocity estimate (e.g. from the
    /// platform's own gesture recognizer) should prefer it over a `0` born
    /// from too little data rather than from genuinely no motion.
    public var sampleCount: Int { samples.count }

    /// The estimated velocity (points/second) at the most recent sample, or
    /// `0` if there isn't enough data yet.
    public var velocity: Double {
        guard let latest = samples.last, samples.count >= 2 else { return 0 }

        // Weighted least-squares fit of a line `position = a + b * t`. Recentering
        // time so the latest sample sits at t = 0 doesn't change the fitted slope,
        // but it does make "age" (and therefore the recency weight) simple to read.
        var sumW = 0.0, sumWT = 0.0, sumWP = 0.0, sumWTT = 0.0, sumWTP = 0.0

        for sample in samples {
            let t = sample.time - latest.time
            let age = -t
            let weight = max(0, 1 - age / historyDuration)

            sumW += weight
            sumWT += weight * t
            sumWP += weight * sample.position
            sumWTT += weight * t * t
            sumWTP += weight * t * sample.position
        }

        let denominator = sumW * sumWTT - sumWT * sumWT
        guard abs(denominator) > .ulpOfOne else { return 0 }

        // Slope of the fitted line, i.e. velocity at t = 0 (the latest sample).
        return (sumW * sumWTP - sumWT * sumWP) / denominator
    }
}
