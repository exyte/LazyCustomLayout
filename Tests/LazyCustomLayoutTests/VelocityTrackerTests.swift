import Testing
@testable import LazyCustomLayout

@Suite("VelocityTracker")
struct VelocityTrackerTests {

    @Test("no samples yields zero velocity")
    func noSamplesIsZero() {
        let tracker = VelocityTracker()

        #expect(tracker.velocity == 0)
    }

    @Test("a single sample yields zero velocity")
    func singleSampleIsZero() {
        var tracker = VelocityTracker()
        tracker.addSample(time: 0, position: 10)

        #expect(tracker.velocity == 0)
    }

    @Test("constant-velocity samples recover that velocity")
    func constantVelocityIsRecovered() {
        var tracker = VelocityTracker(historyDuration: 0.1)
        let v = 800.0 // points/second
        let dt = 0.01

        for i in 0...8 {
            let t = Double(i) * dt
            tracker.addSample(time: t, position: v * t)
        }

        #expect(abs(tracker.velocity - v) < 1.0)
    }

    @Test("noisy samples around a constant velocity recover it within tolerance")
    func noisyVelocityIsApproximatelyRecovered() {
        var tracker = VelocityTracker(historyDuration: 0.1)
        let v = 500.0
        let dt = 0.01
        let noise = [1.0, -1.0, 0.5, -0.5, 1.0, -1.0, 0.5, -0.5, 0.0]

        for i in 0...8 {
            let t = Double(i) * dt
            tracker.addSample(time: t, position: v * t + noise[i])
        }

        #expect(abs(tracker.velocity - v) < 20.0)
    }

    @Test("a stop at the end of the drag pulls the estimate toward zero")
    func recentStopPullsEstimateDown() {
        var tracker = VelocityTracker(historyDuration: 0.1)
        let v = 1000.0

        // Moves steadily for 80ms, then stays still for the last 20ms.
        for i in 0...8 {
            let t = Double(i) * 0.01
            tracker.addSample(time: t, position: v * t)
        }
        let stoppedAt = tracker.velocity > 0 ? 0.08 * v : 0 // position when the stop begins
        for i in 0...2 {
            let t = 0.08 + Double(i) * 0.01
            tracker.addSample(time: t, position: stoppedAt)
        }

        #expect(tracker.velocity < v * 0.9)
    }

    @Test("samples older than historyDuration are dropped")
    func oldSamplesAreDropped() {
        var tracker = VelocityTracker(historyDuration: 0.1)
        tracker.addSample(time: 0, position: 0)
        tracker.addSample(time: 0.5, position: 1000) // far beyond the 100ms window

        // Only the most recent sample remains, so there isn't enough data for a fit.
        #expect(tracker.velocity == 0)
    }

    @Test("reset clears recorded samples")
    func resetClearsSamples() {
        var tracker = VelocityTracker()
        tracker.addSample(time: 0, position: 0)
        tracker.addSample(time: 0.01, position: 10)
        tracker.reset()
        tracker.addSample(time: 1, position: 0)

        #expect(tracker.velocity == 0)
    }

    @Test("sampleCount reflects only samples within historyDuration")
    func sampleCountTracksRetainedSamples() {
        var tracker = VelocityTracker(historyDuration: 0.1)

        #expect(tracker.sampleCount == 0)

        tracker.addSample(time: 0, position: 0)
        #expect(tracker.sampleCount == 1)

        tracker.addSample(time: 0.01, position: 10)
        #expect(tracker.sampleCount == 2)

        tracker.addSample(time: 0.5, position: 1000) // drops the earlier two samples
        #expect(tracker.sampleCount == 1)
    }
}
