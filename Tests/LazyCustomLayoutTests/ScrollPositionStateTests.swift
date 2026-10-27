import Testing
@testable import LazyCustomLayout

@MainActor
@Suite("ScrollPositionState")
struct ScrollPositionStateTests {

    func makeState(
        ids: [Int] = [0, 1, 2, 3, 4],
        sizes: [Int: Double] = [0: 100, 1: 100, 2: 100, 3: 100, 4: 100],
        anchor: ScrollAnchor<Int> = ScrollAnchor(id: 0),
        loadedIDs: Set<Int>? = nil
    ) -> (state: ScrollPositionState<FakeAnchorDataSource>, clock: FakeFrameDriving) {
        let dataSource = FakeAnchorDataSource(ids: ids, loadedIDs: loadedIDs)
        let sizeCache = SizeCache<Int>()
        for (id, size) in sizes { sizeCache[id] = size }

        let clock = FakeFrameDriving()
        let state = ScrollPositionState(anchor: anchor, dataSource: dataSource, sizeCache: sizeCache, clock: clock)
        return (state, clock)
    }

    // MARK: Jump

    @Test("scrollTo jumps straight to the target without animating")
    func scrollToJumpsImmediately() {
        let (state, clock) = makeState()

        state.scrollTo(id: 3, offset: 20)

        #expect(state.anchor == ScrollAnchor(id: 3, offset: 20))
        #expect(!clock.isRunning)
    }

    // MARK: Applying deltas

    @Test("applyDelta moves the anchor the same way the resolver does")
    func applyDeltaMovesAnchor() {
        let (state, _) = makeState()

        state.applyDelta(150)

        #expect(state.anchor == ScrollAnchor(id: 1, offset: 50))
    }

    @Test("applyDelta past the last item fires onReachEnd")
    func applyDeltaPastLastItemFiresOnReachEnd() {
        let (state, _) = makeState(anchor: ScrollAnchor(id: 4, offset: 80))
        var reachedEnd = false
        state.onReachEnd = { reachedEnd = true }

        state.applyDelta(50)

        #expect(reachedEnd)
    }

    @Test("applyDelta past the first item fires onReachStart")
    func applyDeltaPastFirstItemFiresOnReachStart() {
        let (state, _) = makeState(anchor: ScrollAnchor(id: 0, offset: 20))
        var reachedStart = false
        state.onReachStart = { reachedStart = true }

        state.applyDelta(-50)

        #expect(reachedStart)
    }

    // MARK: Animated scroll

    @Test("animateScrollTo animates toward a resolvable target instead of jumping immediately")
    func animateScrollToAnimatesWhenResolvable() {
        let (state, clock) = makeState()

        state.animateScrollTo(id: 2)

        // Still mid-flight right after the call, not already at the target.
        #expect(clock.isRunning)
        #expect(state.anchor != ScrollAnchor(id: 2, offset: 0))

        clock.run(frames: 600, deltaTime: 1.0 / 60.0)

        #expect(!clock.isRunning)
        #expect(state.anchor.id == 2)
        #expect(state.anchor.offset < 1)
    }

    @Test("animateScrollTo jumps immediately when the distance can't be resolved")
    func animateScrollToJumpsWhenUnresolvable() {
        let (state, clock) = makeState(anchor: ScrollAnchor(id: 0, offset: 0), loadedIDs: [0])

        state.animateScrollTo(id: 2)

        #expect(state.anchor == ScrollAnchor(id: 2, offset: 0))
        #expect(!clock.isRunning)
    }
}
