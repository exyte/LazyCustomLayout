import Observation

/// Public entry point for controlling and observing scroll position in terms
/// of an anchor (item id + offset) instead of an absolute offset. Wraps an
/// `AnchorResolver`, adding jump/animated scrolling and start/end-of-data
/// callbacks for paging more data in.
@MainActor
@Observable
public final class ScrollPositionState<DataSource: AnchorResolverDataSource> {
    public typealias ID = DataSource.ID

    public private(set) var anchor: ScrollAnchor<ID>

    public var onReachStart: (() -> Void)?
    public var onReachEnd: (() -> Void)?

    private let resolver: AnchorResolver<DataSource>
    private let clock: any FrameDriving
    private var animationSpring: ScrollPhysics.Spring?

    public init(
        anchor: ScrollAnchor<ID>,
        dataSource: DataSource,
        sizeCache: SizeCache<ID>,
        clock: any FrameDriving = FrameClock()
    ) {
        self.anchor = anchor
        self.resolver = AnchorResolver(anchor: anchor, dataSource: dataSource, sizeCache: sizeCache)
        self.clock = clock
    }

    // MARK: Jump & animated scroll

    /// Jumps straight to `id`, landing with `offset` already scrolled into
    /// it (0 = its leading edge at the top of the viewport).
    public func scrollTo(id: ID, offset: Double = 0) {
        clock.stop()
        animationSpring = nil
        resolver.setAnchor(ScrollAnchor(id: id, offset: offset))
        anchor = resolver.anchor
    }

    /// Scrolls to `id` with motion: if the distance to it can be resolved
    /// from already-measured sizes within `maxResolvableSteps` items, animates
    /// that real distance; otherwise jumps straight there, since animating a
    /// distance that isn't actually known yet would just be a guess.
    public func animateScrollTo(id: ID, maxResolvableSteps: Int = 30) {
        guard let distance = resolveDistance(to: id, maxSteps: maxResolvableSteps) else {
            scrollTo(id: id)
            return
        }

        animate(by: distance)
    }

    // MARK: Applying deltas

    /// Applies `delta` to the anchor, same as the underlying resolver, and
    /// fires `onReachStart`/`onReachEnd` when it runs off the true data ends.
    @discardableResult
    public func applyDelta(_ delta: Double) -> AnchorResolver<DataSource>.Leftover {
        let leftover = resolver.applyDelta(delta)
        anchor = resolver.anchor

        switch leftover {
        case .dataEnd(let remaining) where remaining < 0:
            onReachStart?()
        case .dataEnd(let remaining) where remaining > 0:
            onReachEnd?()
        default:
            break
        }

        return leftover
    }

    // MARK: Distance resolution

    private func resolveDistance(to targetID: ID, maxSteps: Int) -> Double? {
        if targetID == anchor.id {
            return -anchor.offset
        }

        if let forward = resolveForwardDistance(to: targetID, maxSteps: maxSteps) {
            return forward
        }

        return resolveBackwardDistance(to: targetID, maxSteps: maxSteps)
    }

    private func resolveForwardDistance(to targetID: ID, maxSteps: Int) -> Double? {
        guard let size = resolver.sizeCache[anchor.id] else { return nil }

        var distance = size - anchor.offset
        var currentID = anchor.id
        var steps = 0

        while steps < maxSteps {
            guard case .item(let nextID) = resolver.dataSource.boundary(after: currentID) else { return nil }
            if nextID == targetID { return distance }

            guard let nextSize = resolver.sizeCache[nextID] else { return nil }
            distance += nextSize
            currentID = nextID
            steps += 1
        }

        return nil
    }

    private func resolveBackwardDistance(to targetID: ID, maxSteps: Int) -> Double? {
        var distance = -anchor.offset
        var currentID = anchor.id
        var steps = 0

        while steps < maxSteps {
            guard case .item(let previousID) = resolver.dataSource.boundary(before: currentID) else { return nil }
            guard let previousSize = resolver.sizeCache[previousID] else { return nil }
            if previousID == targetID { return distance - previousSize }

            distance -= previousSize
            currentID = previousID
            steps += 1
        }

        return nil
    }

    // MARK: Animation

    private func animate(by distance: Double) {
        guard distance != 0 else { return }

        clock.stop()
        animationSpring = ScrollPhysics.Spring(position: 0, velocity: 0, target: distance)
        clock.callback = { [weak self] _, deltaTime in
            self?.tickAnimation(deltaTime: deltaTime)
        }
        clock.start()
    }

    private func tickAnimation(deltaTime: Double) {
        guard var spring = animationSpring else {
            clock.stop()
            return
        }

        let previousPosition = spring.position
        spring.step(dt: deltaTime)

        if spring.isAtRest {
            // Land exactly on the target rather than wherever the rest
            // tolerance happened to leave it — stopping a fraction of a
            // point short of an exact item boundary would otherwise resolve
            // to the previous item at a near-maximal offset instead of the
            // intended one.
            spring.position = spring.target
            animationSpring = nil
            clock.stop()
        } else {
            animationSpring = spring
        }

        applyDelta(spring.position - previousPosition)
    }
}
