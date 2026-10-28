import LazyCustomLayout
import SwiftUI

/// Proves the package needs nothing beyond the public `StreamingLayout`
/// protocol to support a layout the package itself never shipped: a
/// three-tier scattered mosaic — big photos spread out first, then medium
/// ones tucked into the biggest remaining holes, then small ones closing
/// every last gap — each new tile allowed to cover a neighbor by only a
/// little, the same wall of overlapping-but-not-messy covers a real
/// collage poster uses. Built entirely in example code and handed
/// straight to `LazyAnchoredScroll`.
///
/// Cell reuse is turned off: with real overlap between neighbors, the
/// stacking order (who's drawn on top) has to track ascending index, which
/// is only guaranteed by the window's own index order, not by the reuse
/// pool's slot order.
struct CollageExample: View {
    private static let itemCount = 400

    var body: some View {
        LazyAnchoredScroll(0..<Self.itemCount, layout: CollageLayout(), estimatedItemLength: 110) { index in
            AlbumCoverTile(index: index)
        }
        .cellReuse(false)
        .navigationTitle("Collage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A hand-rolled `StreamingLayout`: a three-tier scatter, computed once
/// into `pattern` and then repeated block after block down the scroll
/// axis — tile size/position is a pure function of
/// `context.index % pattern.count`, so there's still no positions class
/// needed to keep state in sync; only the one-time pattern generation is
/// stateful.
private struct CollageLayout: StreamingLayout {
    private static let pattern: [CGRect] = makePattern()

    /// Square photo tiles fill a `canvasUnits`-wide, `canvasRows`-tall
    /// canvas (in unit coordinates); the whole canvas repeats down the
    /// scroll axis as one block. The three size tiers below are in these
    /// same unit coordinates, so `canvasUnits` is also what pins them to
    /// an actual screen fraction: the biggest tier is 2 units, and
    /// `2 / canvasUnits == 1/3` is exactly why this is 6.
    private static let canvasUnits = 6.0
    private static let canvasRows = 10.0

    func proposedSize(context: StreamingLayoutContext, cache: inout Void) -> ProposedViewSize {
        let unit = unitLength(context: context)
        let length = Self.pattern[context.index % Self.pattern.count].width * unit

        return ProposedViewSize(width: length, height: length)
    }

    func place(size: CGSize, context: StreamingLayoutContext, cache: inout Void) -> CGRect {
        let unit = unitLength(context: context)
        let itemOrigin = origin(forIndex: context.index, unit: unit)
        let anchorOrigin = origin(forIndex: context.anchor.id, unit: unit)
        let mainOrigin = itemOrigin.main - anchorOrigin.main

        switch context.axis {
        case .vertical: return CGRect(x: itemOrigin.cross, y: mainOrigin, width: size.width, height: size.height)
        case .horizontal: return CGRect(x: mainOrigin, y: itemOrigin.cross, width: size.width, height: size.height)
        }
    }

    private func unitLength(context: StreamingLayoutContext) -> Double {
        let totalCross = context.axis == .vertical ? context.viewportSize.width : context.viewportSize.height
        return totalCross / Self.canvasUnits
    }

    private func origin(forIndex index: Int, unit: Double) -> (cross: Double, main: Double) {
        let blockIndex = index / Self.pattern.count
        let tile = Self.pattern[index % Self.pattern.count]

        return (cross: tile.minX * unit, main: Double(blockIndex) * Self.canvasRows * unit + tile.minY * unit)
    }

    /// Three tiers, biggest first — 2/1.5/1 units, so the smallest is
    /// exactly half the biggest, and never any smaller: there's no
    /// filler/backstop tier scattering odd-sized scraps into whatever's
    /// left. Gaps close through overlap between real-sized tiles, not a
    /// separate mechanism — any gap neither placement nor permitted
    /// overlap can close just stays a gap.
    ///
    /// Covering a neighbor isn't a flat area fraction — it's weighted by
    /// *where* on the neighbor the overlap falls. `edgeMargin` around
    /// each tile's border is free to cover entirely (that's an intended,
    /// expected look, like photos overlapping at their corners), and the
    /// cost ramps up linearly from there toward the neighbor's center,
    /// which is the part that actually matters when you look at a photo.
    /// Three different tiles each costing a tenth against the same
    /// fourth tile adds up to 30%, just as much a problem as one tile
    /// costing 30% outright, so each existing tile keeps a running total
    /// of cost incurred by everything placed on top of it, not just a
    /// check against the newest candidate in isolation.
    ///
    /// Both directions are checked for every pair, not just "the new
    /// tile covering the old one." This engine's actual paint order isn't
    /// a fixed property of the pattern — it's anchor-relative (forward
    /// from the current scroll anchor paints first, backward from it
    /// paints after), so which of two overlapping tiles ends up on top
    /// can differ depending on where the anchor happens to be, and the
    /// pattern itself is also locally shuffled afterward (see the sort
    /// below) for visual variety instead of every lower tile automatically
    /// covering the one above it. A cost guarantee that only held in one
    /// direction would get silently violated the moment either of those
    /// flips who's actually drawn on top — checking (and budgeting) both
    /// directions up front means the budget holds *regardless* of which
    /// one wins.
    ///
    /// Within that hard budget, placement has two more tricks. First, a
    /// candidate that lands within `snapThreshold` of a neighbor's edge
    /// snaps to touch it exactly — closing a sliver gap a human eye would
    /// read as a mistake, not an accident of collage. Second, instead of
    /// just taking whichever of `candidatesPerTile` random tries is
    /// farthest from its nearest neighbor (which only serves even spread
    /// when a clean spot actually exists), every candidate is scored by
    /// its total cost and the cheapest one wins, falling back to farthest
    /// only to break ties among equally-free spots. That's the
    /// "unavoidable overlap gets centered to split the damage" behavior:
    /// minimizing total cost *is* centering a tile in a hole that's
    /// slightly too small for it, instead of jamming it flush against one
    /// side and taking a bigger bite out of a single neighbor.
    private static func makePattern() -> [CGRect] {
        let edgeMargin = 0.15 // ~10pt on a typical ~65pt-wide unit
        let maxCoverageCost = 0.15
        let snapThreshold = 0.3 // ~20pt
        let candidatesPerTile = 30

        var rects: [CGRect] = []
        var centers: [CGPoint] = []
        /// `coverageSoFar[k]` is the running total cost already incurred
        /// on `rects[k]` by every tile placed on top of it (parallel
        /// array, same indices as `rects`).
        var coverageSoFar: [Double] = []

        /// The cost of `candidate` covering `neighbor`: a 6x6 grid of
        /// sample points across just the overlap region, each weighted
        /// by its own Chebyshev distance from `neighbor`'s center (0 at
        /// the center, 1 at the edge) — zero weight once that distance is
        /// within `edgeMargin` of the edge, ramping linearly to full
        /// weight at the center otherwise — averaged, then scaled by how
        /// much of `neighbor`'s own area the overlap region is, so a
        /// deep-but-tiny nick and a shallow-but-huge swath can still cost
        /// about the same.
        func coverageCost(_ candidate: CGRect, covering neighbor: CGRect) -> Double {
            let intersection = candidate.intersection(neighbor)
            guard !intersection.isNull else { return 0 }

            let half = neighbor.width / 2
            let marginRatio = min(1, edgeMargin / half)
            let center = CGPoint(x: neighbor.midX, y: neighbor.midY)
            let gridSize = 4
            var totalWeight = 0.0

            for ix in 0..<gridSize {
                for iy in 0..<gridSize {
                    let px = intersection.minX + (Double(ix) + 0.5) / Double(gridSize) * intersection.width
                    let py = intersection.minY + (Double(iy) + 0.5) / Double(gridSize) * intersection.height
                    let r = max(abs(px - center.x), abs(py - center.y)) / half
                    guard r < 1 - marginRatio else { continue }
                    totalWeight += 1 - r / (1 - marginRatio)
                }
            }

            let averageWeight = totalWeight / Double(gridSize * gridSize)
            let intersectionArea = Double(intersection.width * intersection.height)
            let neighborArea = Double(neighbor.width * neighbor.height)
            return averageWeight * (intersectionArea / neighborArea)
        }

        /// Checks `candidate` against every already-placed tile and,
        /// when `apply` is true, commits the result: appends `candidate`
        /// to `rects`/`coverageSoFar` and bumps the running cost of
        /// whichever existing tiles it covers. Returns `nil` if the
        /// candidate isn't acceptable (which, with `apply: false`, makes
        /// this a pure dry-run check), otherwise the candidate's *total*
        /// cost — summed over both directions for every pair (see the
        /// doc above for why it's both, not just "the new tile covering
        /// the old one") — so callers scoring candidates don't need a
        /// second pass over every neighbor just to get a number this pass
        /// already computed.
        @discardableResult
        func tryAccept(_ candidate: CGRect, apply: Bool) -> Double? {
            var incomingForCandidate = 0.0
            var totalCost = 0.0
            var deltas: [(index: Int, cost: Double)] = []

            for (k, neighbor) in rects.enumerated() {
                let costOfCoveringNeighbor = coverageCost(candidate, covering: neighbor)
                guard coverageSoFar[k] + costOfCoveringNeighbor <= maxCoverageCost else { return nil }

                let costOfBeingCoveredByNeighbor = coverageCost(neighbor, covering: candidate)
                incomingForCandidate += costOfBeingCoveredByNeighbor
                guard incomingForCandidate <= maxCoverageCost else { return nil }

                deltas.append((k, costOfCoveringNeighbor))
                totalCost += costOfCoveringNeighbor + costOfBeingCoveredByNeighbor
            }

            guard apply else { return totalCost }

            for delta in deltas { coverageSoFar[delta.index] += delta.cost }
            rects.append(candidate)
            coverageSoFar.append(incomingForCandidate)
            return totalCost
        }

        /// Pulls `candidate` to touch any already-placed neighbor it's
        /// within `snapThreshold` of — independently on each axis, so a
        /// candidate near two different neighbors can snap to touch both
        /// — rather than leaving a gap too small to read as intentional.
        /// Only ever closes a real, positive gap down to exactly zero,
        /// never the reverse, so this can't turn a clean placement into
        /// an overlapping one.
        func snapped(_ candidate: CGRect) -> CGRect {
            var result = candidate

            for neighbor in rects {
                let verticalOverlap = min(result.maxY, neighbor.maxY) - max(result.minY, neighbor.minY)
                if verticalOverlap > 0 {
                    if neighbor.maxX <= result.minX {
                        let gap = result.minX - neighbor.maxX
                        if gap > 0, gap < snapThreshold { result.origin.x -= gap }
                    } else if result.maxX <= neighbor.minX {
                        let gap = neighbor.minX - result.maxX
                        if gap > 0, gap < snapThreshold { result.origin.x += gap }
                    }
                }

                let horizontalOverlap = min(result.maxX, neighbor.maxX) - max(result.minX, neighbor.minX)
                if horizontalOverlap > 0 {
                    if neighbor.maxY <= result.minY {
                        let gap = result.minY - neighbor.maxY
                        if gap > 0, gap < snapThreshold { result.origin.y -= gap }
                    } else if result.maxY <= neighbor.minY {
                        let gap = neighbor.minY - result.maxY
                        if gap > 0, gap < snapThreshold { result.origin.y += gap }
                    }
                }
            }

            return result
        }

        /// Tries `candidatesPerTile` random positions (snapping each
        /// toward nearby neighbors first) and keeps whichever *valid* one
        /// (passing `tryAccept`'s real cumulative-cost check) has the
        /// lowest total cost — ties (most commonly, multiple genuinely
        /// free positions) broken by farthest-from-nearest-neighbor, for
        /// even spread the way Mitchell's best-candidate algorithm
        /// intends. Checking validity before ranking matters once tiles
        /// have real, varying size: a point can be far from every
        /// existing center and still sit right on top of a big tile's
        /// edge, so an earlier revision that ranked by distance *before*
        /// checking validity often had its "best" candidate turn out
        /// invalid anyway. With no neighbors yet (the very first tile),
        /// everything ties at zero cost and infinite distance, so the
        /// first candidate tried wins.
        @discardableResult
        func tryPlace(size: Double) -> Bool {
            let half = size / 2
            var best: CGRect?
            var bestCost = Double.infinity
            var bestNearestNeighborDistance = -Double.infinity

            for _ in 0..<candidatesPerTile {
                let center = CGPoint(
                    x: Double.random(in: half...(canvasUnits - half)),
                    y: Double.random(in: half...(canvasRows - half))
                )
                var candidate = CGRect(x: center.x - half, y: center.y - half, width: size, height: size)
                let snappedCandidate = snapped(candidate)
                let cost: Double
                if let snappedCost = tryAccept(snappedCandidate, apply: false) {
                    candidate = snappedCandidate
                    cost = snappedCost
                } else if let plainCost = tryAccept(candidate, apply: false) {
                    cost = plainCost
                } else {
                    continue
                }

                let candidateCenter = CGPoint(x: candidate.midX, y: candidate.midY)
                let nearestNeighborDistance = centers.map { distance($0, candidateCenter) }.min() ?? .infinity

                if cost < bestCost || (cost == bestCost && nearestNeighborDistance > bestNearestNeighborDistance) {
                    bestCost = cost
                    bestNearestNeighborDistance = nearestNeighborDistance
                    best = candidate
                }
            }

            guard let candidate = best else { return false }

            tryAccept(candidate, apply: true)
            centers.append(CGPoint(x: candidate.midX, y: candidate.midY))
            return true
        }

        for _ in 0..<6 { tryPlace(size: 2) }
        for _ in 0..<14 { tryPlace(size: 1.5) }

        // The smallest of the three real sizes closes most of what's
        // left, relying on the same permitted overlap rather than a
        // separate filler mechanism. A fixed attempt budget (not a
        // coverage target) is generous but bounded; a run of consecutive
        // failures is a strong enough signal that no room is left to cut
        // it short rather than spend the rest of the budget confirming
        // that. Whatever's still empty after this stays empty.
        var consecutiveFailures = 0
        for _ in 0..<200 where consecutiveFailures < 30 {
            if tryPlace(size: 1) {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
            }
        }

        // `StreamingLayoutWalker` assumes ascending index means
        // monotonically further along the main axis — true for every
        // built-in layout, since each one places index N+1 strictly after
        // index N. A scatter pack violates that if left in placement
        // order: an early index could land near the block's bottom,
        // tripping the walker's "reached far enough" check long before
        // the rest of the block is visited, stranding everything after it
        // unwalked. Sorting by vertical origin restores the invariant
        // without touching cross-axis scatter at all.
        let sortedByPosition = rects.sorted { $0.minY < $1.minY }

        // Sorted index order is also *roughly* this engine's paint order
        // (ascending index draws later/on top, within whichever of the
        // forward/backward halves of a window a given index falls into —
        // see `tryAccept`'s doc for why that's "roughly," not exactly).
        // Left as a plain sort, z-order would track vertical position
        // almost exactly: whichever of two overlapping tiles starts lower
        // would almost always end up on top of the one above it. Shuffling
        // within small windows breaks that correlation locally (tiles
        // close enough in `minY` to actually be the ones overlapping each
        // other get their relative order randomized) while leaving it
        // intact globally (each window as a whole still advances forward,
        // so the walker's own invariant above isn't at risk — a window
        // this small can't make `axisEnd` dip anywhere near the
        // viewport-sized `reach` the walker checks against). The
        // coverage-cost budget doesn't depend on any of this holding
        // exactly, by construction — see `tryAccept`.
        let shuffleWindow = 3
        var mixed: [CGRect] = []
        mixed.reserveCapacity(sortedByPosition.count)
        var start = 0
        while start < sortedByPosition.count {
            let end = min(start + shuffleWindow, sortedByPosition.count)
            mixed.append(contentsOf: sortedByPosition[start..<end].shuffled())
            start = end
        }

        return mixed
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let squaredDistance = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
        return squaredDistance.squareRoot()
    }

    /// A fixed paint-order value for the tile at `index`, for `AlbumCoverTile`
    /// to apply as an explicit `.zIndex(_:)`. This engine's own traversal
    /// order isn't a reliable stand-in for "who's on top" — it's
    /// anchor-relative (forward from the current scroll anchor is walked
    /// before backward from it), so which of two overlapping tiles comes
    /// first in the rendered `ForEach` can flip depending on where the
    /// anchor happens to be, which flips visibly as you scroll. An
    /// explicit z-index pinned to each tile's fixed position in `pattern`
    /// (not to the anchor-relative traversal order) sidesteps that
    /// entirely — SwiftUI's `.zIndex(_:)` controls paint order directly,
    /// regardless of declaration or traversal order within the ZStack.
    static func zIndex(forIndex index: Int) -> Double {
        Double(index % pattern.count)
    }
}

/// A real photo filling its tile exactly, cropped (never distorted) to
/// whatever aspect ratio `CollageLayout` hands it.
private struct AlbumCoverTile: View {
    var index: Int

    var body: some View {
        AlbumArt.image(for: index)
            .resizable()
            .scaledToFill()
            .clipped()
            .zIndex(CollageLayout.zIndex(forIndex: index))
    }
}

/// The collage photos (`Album01`...`Album20` in the asset catalog), cycled
/// through by index.
private enum AlbumArt {
    private static let photoCount = 20

    static func image(for index: Int) -> Image {
        Image(String(format: "Album%02d", index % photoCount + 1))
    }
}

#Preview {
    NavigationStack {
        CollageExample()
    }
}
