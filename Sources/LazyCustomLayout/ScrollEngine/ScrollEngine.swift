import Foundation

/// Supplies the information `ScrollEngine` needs but deliberately doesn't own:
/// how big the viewport is, and how much room is left before an edge.
@MainActor
public protocol ScrollEngineDelegate: AnyObject {
    /// Viewport length along the scroll axis, points.
    func scrollEngineViewportLength(_ engine: ScrollEngine) -> Double

    /// How much farther the content can move in `direction` before reaching
    /// that edge, points. `nil` means the edge's position isn't known yet —
    /// e.g. not enough content has streamed in to tell — so the engine treats
    /// it as unbounded and won't rubber-band.
    func scrollEngine(_ engine: ScrollEngine, slackInDirection direction: ScrollEngine.Direction) -> Double?
}

/// Drives one scroll axis: turns raw drag and fling motion into a stream of
/// deltas, handling rubber-banding at the edges and the spring-back once the
/// finger lifts or a fling runs into an edge.
///
/// The engine carries no absolute position and no content size of its own —
/// it asks its delegate how much farther the content can move before an
/// edge, and reports everything else as a delta via `onDelta` for the caller
/// (the anchor model) to apply. A vertical and a horizontal scroll view each
/// get their own engine.
@MainActor
public final class ScrollEngine {

    public enum Direction {
        case forward
        case backward
    }

    public enum State: Equatable {
        case idle
        case dragging
        case flinging
        case springing
    }

    public weak var delegate: ScrollEngineDelegate?

    /// Called with each delta to apply to the scroll position, already
    /// clamped/rubber-banded against the delegate's reported slack.
    public var onDelta: ((Double) -> Void)?
    public var onStateChange: ((State) -> Void)?

    public private(set) var state: State = .idle {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    private let clock: any FrameDriving
    private var velocityTracker = VelocityTracker()
    private var dragCumulativePosition: Double = 0

    /// Distance already dragged/flung past an edge, in "honest" (pre-rubber-band)
    /// units. Zero when not overscrolled; positive past the forward edge,
    /// negative past the backward edge.
    private var overscroll: Double = 0

    // Fling bookkeeping, in the fling's own local coordinate space (starts at
    // 0 when the fling begins), so `ScrollPhysics`'s functions can be used
    // directly without the engine needing an absolute position of its own.
    private var flingStartVelocity: Double = 0
    private var flingElapsed: Double = 0
    private var flingLocalPosition: Double = 0

    private var spring: ScrollPhysics.Spring?

    /// Whether the content had no room to scroll in either direction at the
    /// start of the current gesture — matches `UIScrollView`'s default of
    /// not bouncing when content doesn't overflow the viewport. Computed
    /// once per drag (not per delta) since re-querying both directions'
    /// slack on every tick would double the delegate's layout-walking cost
    /// for no benefit: whether content fits doesn't change mid-gesture.
    private var contentFitsViewport = false

    public init(clock: any FrameDriving) {
        self.clock = clock
        clock.callback = { [weak self] _, deltaTime in
            self?.tick(deltaTime: deltaTime)
        }
    }

    // MARK: Drag

    /// Call for every incremental update while a finger is down, with the
    /// delta since the previous call and a monotonically increasing timestamp
    /// (seconds) used for velocity estimation.
    public func dragChanged(delta: Double, time: Double) {
        if state != .dragging {
            stopAnimating()
            state = .dragging
            velocityTracker.reset()
            dragCumulativePosition = 0
            contentFitsViewport = (delegate?.scrollEngine(self, slackInDirection: .forward) ?? .infinity) == 0
                && (delegate?.scrollEngine(self, slackInDirection: .backward) ?? .infinity) == 0
        }

        dragCumulativePosition += delta
        velocityTracker.addSample(time: time, position: dragCumulativePosition)
        applyRawDelta(delta)
    }

    /// Call when the finger lifts. Transitions to a fling, a spring-back, or
    /// straight to rest, depending on the velocity and whether the content is
    /// currently overscrolled.
    ///
    /// `fallbackVelocity` is used whenever `dragChanged` was called too few
    /// times this drag for `VelocityTracker` to fit a line — a sharp, short
    /// flick can end before a second `.changed` event ever arrives, in which
    /// case the tracker reports `0` regardless of how fast the motion really
    /// was. Pass the platform gesture recognizer's own velocity estimate
    /// (e.g. `UIPanGestureRecognizer.velocity(in:)`) here so that case still
    /// flings instead of silently dropping the gesture.
    public func dragEnded(fallbackVelocity: Double = 0) {
        guard state == .dragging else { return }

        guard !contentFitsViewport else {
            state = .idle
            return
        }

        let velocity = velocityTracker.sampleCount >= 2 ? velocityTracker.velocity : fallbackVelocity

        if overscroll != 0 {
            beginSpring(initialVelocity: velocity)
        } else if abs(velocity) > ScrollPhysics.restVelocity {
            beginFling(initialVelocity: velocity)
        } else {
            state = .idle
        }
    }

    /// Call the instant a finger touches the content again — including while
    /// a fling or spring is still running — to stop any animation in place,
    /// matching `UIScrollView`'s touch-to-stop behavior.
    public func touchDown() {
        stopAnimating()
        state = .idle
    }

    // MARK: Fling & spring

    private func beginFling(initialVelocity: Double) {
        flingStartVelocity = initialVelocity
        flingElapsed = 0
        flingLocalPosition = 0
        state = .flinging
        clock.start()
    }

    private func beginSpring(initialVelocity: Double) {
        spring = ScrollPhysics.Spring(position: overscroll, velocity: initialVelocity, target: 0)
        state = .springing
        clock.start()
    }

    private func stopAnimating() {
        clock.stop()
        spring = nil
    }

    private func tick(deltaTime: Double) {
        switch state {
        case .flinging:
            tickFling(deltaTime: deltaTime)
        case .springing:
            tickSpring(deltaTime: deltaTime)
        case .idle, .dragging:
            clock.stop()
        }
    }

    private func tickFling(deltaTime: Double) {
        flingElapsed += deltaTime

        let newLocalPosition = ScrollPhysics.position(
            initialPosition: 0,
            initialVelocity: flingStartVelocity,
            rate: .normal,
            at: flingElapsed
        )
        let delta = newLocalPosition - flingLocalPosition
        flingLocalPosition = newLocalPosition

        applyRawDelta(delta)

        // `applyRawDelta` may have pushed the engine into overscroll, in which
        // case the fling becomes a spring instead of continuing to decay as if
        // nothing were there.
        if overscroll != 0 {
            let currentVelocity = ScrollPhysics.velocity(initialVelocity: flingStartVelocity, rate: .normal, at: flingElapsed)
            beginSpring(initialVelocity: currentVelocity)
            return
        }

        let currentVelocity = ScrollPhysics.velocity(initialVelocity: flingStartVelocity, rate: .normal, at: flingElapsed)
        if abs(currentVelocity) < ScrollPhysics.restVelocity {
            stopAnimating()
            state = .idle
        }
    }

    private func tickSpring(deltaTime: Double) {
        guard var current = spring else { return }

        let previousOverscroll = overscroll
        current.step(dt: deltaTime)
        spring = current
        overscroll = current.position

        // The spring operates directly on `overscroll`, which already
        // represents the honest (pre-rubber-band) distance — the same
        // quantity dragging and flinging accumulate. Route the resulting
        // display delta through the same rubber-band curve for a continuous
        // visual across the handoff from drag/fling to spring.
        let dimension = delegate?.scrollEngineViewportLength(self) ?? 0
        let previousDisplay = displayOffset(forOverscroll: previousOverscroll, dimension: dimension)
        let newDisplay = displayOffset(forOverscroll: overscroll, dimension: dimension)
        if newDisplay != previousDisplay {
            onDelta?(newDisplay - previousDisplay)
        }

        if current.isAtRest {
            overscroll = 0
            stopAnimating()
            state = .idle
        }
    }

    // MARK: Rubber banding

    /// Applies a raw, un-clamped delta (from a drag or a fling tick), splitting
    /// it between "honest" motion — consumed up to whatever slack the delegate
    /// reports before an edge — and rubber-banded overscroll for the rest.
    private func applyRawDelta(_ rawDelta: Double) {
        guard rawDelta != 0 else { return }

        guard overscroll != 0 else {
            applyFromRest(rawDelta)
            return
        }

        let dimension = delegate?.scrollEngineViewportLength(self) ?? 0
        let wouldCrossZero = (overscroll > 0 && overscroll + rawDelta < 0)
            || (overscroll < 0 && overscroll + rawDelta > 0)

        guard wouldCrossZero else {
            applyOverscrollDelta(rawDelta, dimension: dimension)
            return
        }

        // The delta is large enough to carry the content back past the edge and
        // out the other side within a single step (e.g. a big trackpad tick).
        // Settle the overscroll to exactly zero, then re-enter "honest" mode
        // for whatever's left, so a fresh slack query applies to it.
        let toZero = -overscroll
        applyOverscrollDelta(toZero, dimension: dimension)

        let leftover = rawDelta - toZero
        if leftover != 0 {
            applyFromRest(leftover)
        }
    }

    private func applyFromRest(_ rawDelta: Double) {
        guard !contentFitsViewport else { return }

        let direction: Direction = rawDelta > 0 ? .forward : .backward
        let slack = delegate?.scrollEngine(self, slackInDirection: direction) ?? .infinity
        let cappedSlack = max(slack, 0)
        let honest = direction == .forward ? min(rawDelta, cappedSlack) : max(rawDelta, -cappedSlack)

        if honest != 0 {
            onDelta?(honest)
        }

        let remaining = rawDelta - honest
        guard remaining != 0 else { return }

        let dimension = delegate?.scrollEngineViewportLength(self) ?? 0
        applyOverscrollDelta(remaining, dimension: dimension)
    }

    private func applyOverscrollDelta(_ delta: Double, dimension: Double) {
        let previousDisplay = displayOffset(forOverscroll: overscroll, dimension: dimension)
        overscroll += delta
        let newDisplay = displayOffset(forOverscroll: overscroll, dimension: dimension)

        if newDisplay != previousDisplay {
            onDelta?(newDisplay - previousDisplay)
        }
    }

    private func displayOffset(forOverscroll overscroll: Double, dimension: Double) -> Double {
        guard overscroll != 0, dimension > 0 else { return 0 }

        let magnitude = ScrollPhysics.rubberBand(x: abs(overscroll), dimension: dimension)
        return overscroll > 0 ? magnitude : -magnitude
    }
}
