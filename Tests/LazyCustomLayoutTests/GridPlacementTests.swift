import Testing
@testable import LazyCustomLayout

@Suite("GridPlacement")
struct GridPlacementTests {

    // MARK: Packing modes

    @Test("sparse packing never backtracks, leaving a hole a later item could have filled")
    func sparseLeavesHoleBehind() {
        // item0 spans 2 columns at (0,0); item1 also spans 2, doesn't fit
        // column 2 alone, so it drops to row 1 — leaving (2,0) empty, which
        // sparse's forward-only cursor never goes back for.
        let placement = GridPlacement(crossCount: 3, packing: .sparse, crossSpans: [2, 2, 1], mainSpans: [1, 1, 1])

        #expect(placement.cell(for: 0) == (0, 0, 2, 1))
        #expect(placement.cell(for: 1) == (0, 1, 2, 1))
        #expect(placement.cell(for: 2) == (2, 1, 1, 1))
    }

    @Test("dense packing fills the same hole sparse leaves behind")
    func denseFillsTheHole() {
        let placement = GridPlacement(crossCount: 3, packing: .dense, crossSpans: [2, 2, 1], mainSpans: [1, 1, 1])

        #expect(placement.cell(for: 0) == (0, 0, 2, 1))
        #expect(placement.cell(for: 1) == (0, 1, 2, 1))
        #expect(placement.cell(for: 2) == (2, 0, 1, 1))
    }

    // MARK: Calculator parity — both GridSlot tables this type replaced

    @Test("sparse packing reproduces the system calculator's 4-column grid")
    func sparseReproducesSystemCalculator() {
        // percent, +/-, C, ÷, 1,2,3,×, 4,5,6,-, 7,8,9,+, 0(span2),.,=
        let crossSpans = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1]
        let mainSpans = Array(repeating: 1, count: crossSpans.count)
        let placement = GridPlacement(crossCount: 4, packing: .sparse, crossSpans: crossSpans, mainSpans: mainSpans)

        let expected: [(cross: Int, main: Int)] = [
            (0, 0), (1, 0), (2, 0), (3, 0),
            (0, 1), (1, 1), (2, 1), (3, 1),
            (0, 2), (1, 2), (2, 2), (3, 2),
            (0, 3), (1, 3), (2, 3), (3, 3),
            (0, 4), (2, 4), (3, 4),
        ]

        for (index, cell) in expected.enumerated() {
            let placed = placement.cell(for: index)
            #expect((placed.cross, placed.main) == cell, "index \(index)")
        }
    }

    @Test("sparse packing reproduces the alternative calculator's 5-column grid")
    func sparseReproducesAlternativeCalculator() {
        // %(span col3), +/-(span col2),
        // 1,2,3,-,C,
        // 4,5,6,+(span row2),÷,
        // 7,8,9,×,
        // 0,.,=(span col3)
        let crossSpans = [3, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3]
        let mainSpans = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1]
        let placement = GridPlacement(crossCount: 5, packing: .sparse, crossSpans: crossSpans, mainSpans: mainSpans)

        let expected: [(cross: Int, main: Int)] = [
            (0, 0), (3, 0),
            (0, 1), (1, 1), (2, 1), (3, 1), (4, 1),
            (0, 2), (1, 2), (2, 2), (3, 2), (4, 2),
            (0, 3), (1, 3), (2, 3), (4, 3),
            (0, 4), (1, 4), (2, 4),
        ]

        for (index, cell) in expected.enumerated() {
            let placed = placement.cell(for: index)
            #expect((placed.cross, placed.main) == cell, "index \(index)")
        }
    }

    // MARK: Out-of-order queries

    @Test("querying a late index first places every earlier index the same way as querying in order")
    func outOfOrderQueryMatchesInOrder() {
        let inOrder = GridPlacement(crossCount: 3, packing: .sparse, crossSpans: [2, 2, 1, 1], mainSpans: [1, 1, 1, 1])
        for index in 0..<4 { _ = inOrder.cell(for: index) }

        let jumpFirst = GridPlacement(crossCount: 3, packing: .sparse, crossSpans: [2, 2, 1, 1], mainSpans: [1, 1, 1, 1])
        let jumped = jumpFirst.cell(for: 3)

        #expect(jumped == inOrder.cell(for: 3))
        #expect(jumpFirst.cell(for: 0) == inOrder.cell(for: 0))
    }
}

@Suite("resolveGridTracks")
struct ResolveGridTracksTests {

    @Test("px tracks keep their fixed length; fr tracks split whatever's left by weight")
    func mixedPxAndFrTracks() {
        let tracks: [GridTrack] = [.fr(1), .px(150), .fr(2)]

        let resolved = resolveGridTracks(tracks, totalLength: 466, spacing: 8)

        #expect(resolved.map(\.length) == [100, 150, 200])
        #expect(resolved.map(\.origin) == [0, 108, 266])
    }

    @Test("equal fr tracks split the space evenly")
    func equalFrTracks() {
        let resolved = resolveGridTracks([.fr(1), .fr(1), .fr(1)], totalLength: 300, spacing: 0)

        #expect(resolved.map(\.length) == [100, 100, 100])
    }
}
