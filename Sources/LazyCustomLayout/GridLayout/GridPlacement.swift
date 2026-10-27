/// Where each item's cell footprint goes in a `LazyGrid` — a pure
/// function of every earlier item's span, never its size, so it can be
/// computed one item at a time without breaking laziness (unlike track
/// *lengths*, which do depend on measured content for an auto-sized main
/// axis — see `GridLayout`). Spans don't change after being read,
/// so unlike `FlowPositions`'/`MasonryPositions`' size-dependent estimates,
/// this sweep is exact, not a seam: feeding it the same spans in the same
/// order always produces the same cells, streamed one item at a time or
/// not.
///
/// Works entirely in axis-agnostic `cross`/`main` terms, not `column`/`row`
/// — `GridLayout` maps the public, always-column/row `GridSpan`
/// into these based on which way the grid actually scrolls.
///
/// `.sparse` keeps a single forward-only cursor (CSS Grid's own sparse
/// algorithm): each item is placed in the first free cell at or after the
/// cursor, and the cursor only ever advances, so earlier holes it skipped
/// are never revisited. `.dense` instead rescans from the very start for
/// every item, so a smaller item later on can fill a hole an earlier,
/// larger item left behind — matching CSS Grid's own dense semantics.
final class GridPlacement {
    private let crossCount: Int
    private let packing: GridPacking
    private let crossSpans: [Int]
    private let mainSpans: [Int]

    private var assignedCell: [Int: GridCell] = [:]
    private var occupied: Set<GridCell> = []
    private var nextIndexToPlace = 0
    /// `.sparse` only: where the next search starts — never moves backward.
    private var cursor = GridCell(cross: 0, main: 0)

    init(crossCount: Int, packing: GridPacking, crossSpans: [Int], mainSpans: [Int]) {
        self.crossCount = max(1, crossCount)
        self.packing = packing
        self.crossSpans = crossSpans
        self.mainSpans = mainSpans
    }

    /// `index`'s cell and (clamped) span, placing every not-yet-placed
    /// index up to and including it first.
    func cell(for index: Int) -> (cross: Int, main: Int, crossSpan: Int, mainSpan: Int) {
        while nextIndexToPlace <= index {
            place(nextIndexToPlace)
            nextIndexToPlace += 1
        }

        let cell = assignedCell[index] ?? GridCell(cross: 0, main: 0)
        let span = clampedSpan(for: index)

        return (cell.cross, cell.main, span.crossSpan, span.mainSpan)
    }

    private func clampedSpan(for index: Int) -> (crossSpan: Int, mainSpan: Int) {
        let crossSpan = index < crossSpans.count ? crossSpans[index] : 1
        let mainSpan = index < mainSpans.count ? mainSpans[index] : 1

        return (min(max(1, crossSpan), crossCount), max(1, mainSpan))
    }

    private func place(_ index: Int) {
        let span = clampedSpan(for: index)
        let origin = packing == .sparse
            ? firstFit(from: cursor, crossSpan: span.crossSpan, mainSpan: span.mainSpan)
            : firstFit(from: GridCell(cross: 0, main: 0), crossSpan: span.crossSpan, mainSpan: span.mainSpan)

        assignedCell[index] = origin
        for main in origin.main..<(origin.main + span.mainSpan) {
            for cross in origin.cross..<(origin.cross + span.crossSpan) {
                occupied.insert(GridCell(cross: cross, main: main))
            }
        }

        if packing == .sparse {
            cursor = advance(origin)
        }
    }

    private func firstFit(from start: GridCell, crossSpan: Int, mainSpan: Int) -> GridCell {
        var candidate = start

        while !fits(candidate, crossSpan: crossSpan, mainSpan: mainSpan) {
            candidate = advance(candidate)
        }

        return candidate
    }

    private func fits(_ origin: GridCell, crossSpan: Int, mainSpan: Int) -> Bool {
        guard origin.cross + crossSpan <= crossCount else { return false }

        for main in origin.main..<(origin.main + mainSpan) {
            for cross in origin.cross..<(origin.cross + crossSpan) {
                if occupied.contains(GridCell(cross: cross, main: main)) { return false }
            }
        }

        return true
    }

    private func advance(_ cell: GridCell) -> GridCell {
        let nextCross = cell.cross + 1
        return nextCross < crossCount ? GridCell(cross: nextCross, main: cell.main) : GridCell(cross: 0, main: cell.main + 1)
    }
}

private struct GridCell: Hashable {
    var cross: Int
    var main: Int
}
