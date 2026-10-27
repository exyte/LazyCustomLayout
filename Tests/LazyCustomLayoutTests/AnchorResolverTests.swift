import Testing
@testable import LazyCustomLayout

@MainActor
@Suite("AnchorResolver")
struct AnchorResolverTests {

    func makeResolver(
        ids: [Int] = [0, 1, 2, 3, 4],
        sizes: [Int: Double] = [0: 100, 1: 100, 2: 100, 3: 100, 4: 100],
        anchor: ScrollAnchor<Int> = ScrollAnchor(id: 0),
        loadedIDs: Set<Int>? = nil
    ) -> AnchorResolver<FakeAnchorDataSource> {
        let dataSource = FakeAnchorDataSource(ids: ids, loadedIDs: loadedIDs)
        let sizeCache = SizeCache<Int>()
        for (id, size) in sizes { sizeCache[id] = size }

        return AnchorResolver(anchor: anchor, dataSource: dataSource, sizeCache: sizeCache)
    }

    // MARK: Within one item

    @Test("a delta within the current item's size just moves the offset")
    func deltaWithinItemMovesOffset() {
        let resolver = makeResolver()

        let leftover = resolver.applyDelta(40)

        #expect(leftover == .none)
        #expect(resolver.anchor == ScrollAnchor(id: 0, offset: 40))
    }

    // MARK: Crossing boundaries

    @Test("a forward delta past the current item's size crosses into the next one")
    func forwardDeltaCrossesIntoNextItem() {
        let resolver = makeResolver()

        let leftover = resolver.applyDelta(150)

        #expect(leftover == .none)
        #expect(resolver.anchor == ScrollAnchor(id: 1, offset: 50))
    }

    @Test("a backward delta past the current item's offset crosses into the previous one")
    func backwardDeltaCrossesIntoPreviousItem() {
        let resolver = makeResolver(anchor: ScrollAnchor(id: 2, offset: 20))

        let leftover = resolver.applyDelta(-50)

        #expect(leftover == .none)
        #expect(resolver.anchor == ScrollAnchor(id: 1, offset: 70))
    }

    @Test("crossing several item boundaries in one delta lands in the right item")
    func crossingSeveralBoundariesLandsCorrectly() {
        let resolver = makeResolver()

        resolver.applyDelta(250)

        #expect(resolver.anchor == ScrollAnchor(id: 2, offset: 50))
    }

    // MARK: True data ends

    @Test("running past the last item reports the leftover as a positive data end")
    func forwardPastLastItemReportsDataEnd() {
        let resolver = makeResolver(anchor: ScrollAnchor(id: 4, offset: 80))

        let leftover = resolver.applyDelta(50)

        #expect(leftover == .dataEnd(30))
        #expect(resolver.anchor == ScrollAnchor(id: 4, offset: 100))
    }

    @Test("running past the first item reports the leftover as a negative data end")
    func backwardPastFirstItemReportsDataEnd() {
        let resolver = makeResolver(anchor: ScrollAnchor(id: 0, offset: 20))

        let leftover = resolver.applyDelta(-50)

        #expect(leftover == .dataEnd(-30))
        #expect(resolver.anchor == ScrollAnchor(id: 0, offset: 0))
    }

    // MARK: Unloaded neighbors

    @Test("running into an unloaded neighbor reports the leftover as unloaded, not a data end")
    func forwardIntoUnloadedNeighborReportsUnloaded() {
        let resolver = makeResolver(anchor: ScrollAnchor(id: 1, offset: 80), loadedIDs: [0, 1])

        let leftover = resolver.applyDelta(50)

        #expect(leftover == .unloaded(30))
        #expect(resolver.anchor == ScrollAnchor(id: 1, offset: 100))
    }

    @Test("starting from an item whose own size isn't measured yet reports unloaded immediately")
    func forwardFromUnmeasuredItemReportsUnloaded() {
        let resolver = makeResolver()
        resolver.sizeCache[0] = nil

        let leftover = resolver.applyDelta(10)

        #expect(leftover == .unloaded(10))
        #expect(resolver.anchor == ScrollAnchor(id: 0, offset: 0))
    }

    @Test("crossing into a loaded neighbor whose size isn't measured yet reports unloaded")
    func backwardIntoUnmeasuredNeighborReportsUnloaded() {
        let resolver = makeResolver(anchor: ScrollAnchor(id: 1, offset: 20))
        resolver.sizeCache[0] = nil

        let leftover = resolver.applyDelta(-50)

        #expect(leftover == .unloaded(-30))
        #expect(resolver.anchor == ScrollAnchor(id: 0, offset: 0))
    }
}
