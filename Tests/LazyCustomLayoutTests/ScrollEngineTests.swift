import Testing
@testable import LazyCustomLayout

@MainActor
@Suite("ScrollEngine")
struct ScrollEngineTests {

    func makeEngine() -> (engine: ScrollEngine, clock: FakeFrameDriving, delegate: FakeScrollEngineDelegate, deltas: Box<[Double]>) {
        let clock = FakeFrameDriving()
        let delegate = FakeScrollEngineDelegate()
        let engine = ScrollEngine(clock: clock)
        engine.delegate = delegate

        let deltas = Box<[Double]>([])
        engine.onDelta = { [weak delegate] delta in
            deltas.value.append(delta)
            // Approximates the edge "approaching" as the engine reports motion
            // toward it. Good enough to drive these tests; not a claim that
            // visual (rubber-banded) motion should count as real progress.
            if delta > 0 {
                delegate?.forwardEdgeDistance -= delta
            } else {
                delegate?.backwardEdgeDistance += delta
            }
        }

        return (engine, clock, delegate, deltas)
    }

    // MARK: Dragging within slack

    @Test("a drag within the available slack passes straight through")
    func dragWithinSlackPassesThrough() {
        let (engine, _, _, deltas) = makeEngine()

        engine.dragChanged(delta: 10, time: 0)

        #expect(deltas.value == [10])
        #expect(engine.state == .dragging)
    }

    // MARK: Rubber banding

    @Test("a drag beyond the available slack rubber-bands the remainder")
    func dragBeyondSlackRubberBands() {
        let (engine, _, delegate, deltas) = makeEngine()
        delegate.forwardEdgeDistance = 5

        engine.dragChanged(delta: 20, time: 0)

        // 5 honest points, plus a rubber-banded remainder strictly less than
        // the dishonest 15 that was left over.
        #expect(deltas.value.count == 2)
        #expect(deltas.value[0] == 5)
        #expect(deltas.value[1] > 0)
        #expect(deltas.value[1] < 15)
    }

    @Test("dragging deeper into overscroll keeps displacement below one viewport")
    func draggingDeeperStaysBelowViewport() {
        let (engine, _, delegate, deltas) = makeEngine()
        delegate.forwardEdgeDistance = 5
        delegate.viewportLength = 400

        engine.dragChanged(delta: 5000, time: 0)

        let totalDisplayed = deltas.value.reduce(0, +)
        #expect(totalDisplayed < 400)
    }

    @Test("dragging back out of overscroll reduces the displayed offset")
    func draggingBackReducesDisplayedOffset() {
        let (engine, _, delegate, deltas) = makeEngine()
        delegate.forwardEdgeDistance = 5

        engine.dragChanged(delta: 50, time: 0)
        let afterFirstDrag = deltas.value.reduce(0, +)

        engine.dragChanged(delta: -10, time: 0.01)
        let afterSecondDrag = deltas.value.reduce(0, +)

        #expect(afterSecondDrag < afterFirstDrag)
    }

    @Test("crossing back past the edge re-enters honest mode for the leftover")
    func crossingBackPastEdgeReentersHonestMode() {
        let (engine, _, delegate, _) = makeEngine()
        delegate.forwardEdgeDistance = 5
        delegate.backwardEdgeDistance = 100

        engine.dragChanged(delta: 20, time: 0) // 5 honest + 15 overscrolled
        engine.dragChanged(delta: -17, time: 0.01) // back past zero, 2 points of honest backward motion left over

        engine.dragEnded()

        // Only overscroll routes to a spring; being back at rest means the
        // crossing was handled correctly.
        #expect(engine.state != .springing)
    }

    // MARK: Ending a drag

    @Test("ending a drag while overscrolled starts a spring, regardless of velocity")
    func dragEndedWhileOverscrolledStartsSpring() {
        let (engine, clock, delegate, _) = makeEngine()
        delegate.forwardEdgeDistance = 5

        engine.dragChanged(delta: 50, time: 0)
        engine.dragEnded()

        #expect(engine.state == .springing)
        #expect(clock.isRunning)
    }

    @Test("ending a fast drag with no overscroll starts a fling")
    func dragEndedWithVelocityStartsFling() {
        let (engine, clock, _, _) = makeEngine()

        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 15, time: 0.01) // 1500 points/second

        engine.dragEnded()

        #expect(engine.state == .flinging)
        #expect(clock.isRunning)
    }

    @Test("ending a slow drag with no overscroll goes straight to idle")
    func dragEndedSlowGoesIdle() {
        let (engine, clock, _, _) = makeEngine()

        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 0.01, time: 0.5) // far below the rest-velocity threshold

        engine.dragEnded()

        #expect(engine.state == .idle)
        #expect(!clock.isRunning)
    }

    @Test("a single-sample drag falls back to the caller's velocity instead of flattening to zero")
    func dragEndedWithOneSampleUsesFallbackVelocity() {
        let (engine, clock, _, _) = makeEngine()

        // Only one `dragChanged` call this drag — too few for `VelocityTracker`
        // to fit a line (it needs 2+), which would otherwise report 0 and
        // silently drop what was actually a fast, sharp flick.
        engine.dragChanged(delta: 15, time: 0)

        engine.dragEnded(fallbackVelocity: 1500)

        #expect(engine.state == .flinging)
        #expect(clock.isRunning)
    }

    @Test("a multi-sample drag ignores the fallback velocity in favor of its own estimate")
    func dragEndedWithEnoughSamplesIgnoresFallbackVelocity() {
        let (engine, clock, _, _) = makeEngine()

        // Both samples land within `historyDuration` (0.1s default), so the
        // tracker retains both and computes its own (slow) velocity instead
        // of falling back.
        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 0.01, time: 0.01) // 1 point/second, far below the rest-velocity threshold

        engine.dragEnded(fallbackVelocity: 1500)

        #expect(engine.state == .idle)
        #expect(!clock.isRunning)
    }

    // MARK: Content fits viewport

    @Test("dragging content that already fits the viewport in both directions produces no motion")
    func dragWithContentFittingViewportProducesNoDeltas() {
        let (engine, _, delegate, deltas) = makeEngine()
        delegate.forwardEdgeDistance = 0
        delegate.backwardEdgeDistance = 0

        engine.dragChanged(delta: 50, time: 0)

        #expect(deltas.value.isEmpty)
    }

    @Test("ending a fast drag on content that fits the viewport goes straight to idle, not a fling")
    func dragEndedWithContentFittingViewportSkipsFling() {
        let (engine, clock, delegate, _) = makeEngine()
        delegate.forwardEdgeDistance = 0
        delegate.backwardEdgeDistance = 0

        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 15, time: 0.01) // 1500 points/second — would normally fling

        engine.dragEnded()

        #expect(engine.state == .idle)
        #expect(!clock.isRunning)
    }

    // MARK: Touch to stop

    @Test("touching down during a fling stops it immediately")
    func touchDownDuringFlingStops() {
        let (engine, clock, _, _) = makeEngine()

        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 15, time: 0.01)
        engine.dragEnded()
        #expect(engine.state == .flinging)

        engine.touchDown()

        #expect(engine.state == .idle)
        #expect(!clock.isRunning)
    }

    // MARK: Fling

    @Test("a fling with no edge in reach decays to idle on its own")
    func flingWithNoEdgeDecaysToIdle() {
        let (engine, clock, _, deltas) = makeEngine()

        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 25, time: 1.0 / 60.0) // ~1500 points/second
        engine.dragEnded()
        #expect(engine.state == .flinging)

        clock.run(frames: 400, deltaTime: 1.0 / 60.0)

        #expect(engine.state == .idle)
        #expect(!clock.isRunning)

        let resting = ScrollPhysics.restingPosition(initialPosition: 0, initialVelocity: 1500, rate: .normal)
        let traveled = deltas.value.reduce(0, +)
        #expect(abs(traveled - resting) < resting * 0.1)
    }

    @Test("a fling that reaches an edge becomes a spring, then settles to idle")
    func flingIntoEdgeBecomesSpringThenIdle() {
        let (engine, clock, delegate, _) = makeEngine()
        delegate.forwardEdgeDistance = 40

        var observedStates: [ScrollEngine.State] = []
        engine.onStateChange = { observedStates.append($0) }

        engine.dragChanged(delta: 0, time: 0)
        engine.dragChanged(delta: 25, time: 1.0 / 60.0) // ~1500 points/second
        engine.dragEnded()

        clock.run(frames: 600, deltaTime: 1.0 / 60.0)

        #expect(observedStates.contains(.flinging))
        #expect(observedStates.contains(.springing))
        #expect(engine.state == .idle)
        #expect(!clock.isRunning)
    }
}

/// A reference type used to let test closures mutate a captured value, since
/// Swift Testing test methods can't capture `inout` locals in closures.
final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
