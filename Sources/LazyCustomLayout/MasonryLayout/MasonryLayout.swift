import SwiftUI

/// `lanes` equal-width columns, each item going into whichever lane is
/// currently shortest — classic Pinterest-style masonry grid.
///
/// A lane choice is permanent once made; an item's position is not — it's
/// recomputed every call from the lane's current best-known lengths.
/// Locking position too (not just lane) was tried and reverted: an early
/// size guess got baked into every later item's offset in that lane,
/// leaving a gap or overlap that could never self-correct once the real
/// size came in. See `MasonryPositions`.
public struct MasonryLayout: StreamingLayout {
    public var lanes: Int
    public var spacing: Double

    private let positions: MasonryPositions

    public init(lanes: Int, spacing: Double = 0) {
        self.lanes = max(lanes, 1)
        self.spacing = spacing
        self.positions = MasonryPositions(lanes: self.lanes)
    }

    public func proposedSize(context: StreamingLayoutContext, cache: inout Void) -> ProposedViewSize {
        let length = laneLength(context: context)
        switch context.axis {
        case .vertical: return ProposedViewSize(width: length, height: nil)
        case .horizontal: return ProposedViewSize(width: nil, height: length)
        }
    }

    public func place(size: CGSize, context: StreamingLayoutContext, cache: inout Void) -> CGRect {
        let laneLength = laneLength(context: context)
        let mainLength = context.axis == .vertical ? size.height : size.width

        let (lane, globalOrigin) = positions.position(
            for: context.index,
            isAnchor: context.neighborFrame == nil,
            lanes: lanes,
            mainLength: mainLength,
            spacing: spacing
        )

        // Translate from the shared coordinate space into one where the
        // *current* anchor sits at local origin 0, which is what the rest of
        // the system (offset math, slack) expects — the anchor is always
        // placed before any other item in the same window pass, so its
        // origin is always already known here.
        let localOrigin = globalOrigin - positions.currentAnchorOrigin

        return frame(lane: lane, origin: localOrigin, size: size, laneLength: laneLength, context: context)
    }

    private func laneLength(context: StreamingLayoutContext) -> Double {
        let totalCross = context.axis == .vertical ? context.viewportSize.width : context.viewportSize.height
        // Clamped: during a navigation push's transition, the container can
        // be momentarily narrower than `spacing` alone, which would
        // otherwise go negative and trip SwiftUI's invalid-frame warning.
        return max(0, (totalCross - spacing * Double(lanes - 1)) / Double(lanes))
    }

    private func frame(lane: Int, origin: Double, size: CGSize, laneLength: Double, context: StreamingLayoutContext) -> CGRect {
        let crossOrigin = Double(lane) * (laneLength + spacing)

        switch context.axis {
        case .vertical: return CGRect(x: crossOrigin, y: origin, width: laneLength, height: size.height)
        case .horizontal: return CGRect(x: origin, y: crossOrigin, width: size.width, height: laneLength)
        }
    }

    /// `lanes` copies of the widest item — an approximation (real lanes
    /// split *available* space evenly regardless of content), but a
    /// reasonable "natural" width for content with no cross-axis
    /// constraint of its own.
    public func idealCrossLength(itemCrossLengths: [Double]) -> Double {
        let widestItem = itemCrossLengths.max() ?? 0

        return widestItem * Double(lanes) + spacing * Double(lanes - 1)
    }
}

/// Every item's lane, permanently, plus a self-correcting origin recomputed
/// from current sizes on every call — see `MasonryLayout`'s doc for why
/// those two need different stability guarantees.
private final class MasonryPositions {
    private var assignedLane: [Int: Int] = [:]
    /// Each lane's member indices, kept sorted — sorted because an item's
    /// origin is the sum of every *smaller*-index item's length in the same
    /// lane, which on a sorted array is just its contiguous prefix.
    private var laneIndices: [[Int]]
    /// Mirrors `SizeCache`, updated every time an item is placed — reading
    /// `SizeCache` itself would need threading it into this type too; this
    /// is simpler and has the same "self-corrects next time it's placed"
    /// behavior, just one call later for items outside the current window.
    private var lastKnownLength: [Int: Double] = [:]
    /// `laneIndices[lane][assignedPosition[index]] == index` — kept in sync
    /// on every insert so an already-placed item's position is a lookup,
    /// not an `Array.firstIndex` scan.
    private var assignedPosition: [Int: Int] = [:]
    /// `laneCachedOrigins[lane][position]` is the origin of
    /// `laneIndices[lane][position]` — truncated from whichever position's
    /// length changed, or was shifted by an insert, onward. Mirrors
    /// `GridRowLengths`' cache for the same reason: re-summing every
    /// earlier same-lane item on every call made every walk slower the
    /// deeper into a long list it reached.
    private var laneCachedOrigins: [[Double]]
    /// Running total length of each lane, kept in sync the same way, so
    /// picking the shortest lane for a new item is O(1) too.
    private var laneRunningTotal: [Double]

    /// Items whose length has been seen unchanged across two placements —
    /// i.e. measured for real, not an estimate. Only unsettled items may
    /// still change lane, since their lane was picked from guessed sizes.
    private var settledIndices: Set<Int> = []

    private(set) var currentAnchorOrigin: Double = 0

    init(lanes: Int) {
        laneIndices = Array(repeating: [], count: lanes)
        laneCachedOrigins = Array(repeating: [], count: lanes)
        laneRunningTotal = Array(repeating: 0, count: lanes)
    }

    func position(
        for index: Int,
        isAnchor: Bool,
        lanes: Int,
        mainLength: Double,
        spacing: Double
    ) -> (lane: Int, origin: Double) {
        let previousLength = lastKnownLength[index]
        lastKnownLength[index] = mainLength

        if previousLength == mainLength {
            settledIndices.insert(index)
        }

        let lane: Int
        if let existing = assignedLane[index] {
            lane = existing

            if let previousLength, previousLength != mainLength {
                laneRunningTotal[lane] += mainLength - previousLength

                if let position = assignedPosition[index] {
                    invalidateOrigins(lane: lane, fromPosition: position + 1)
                }

                reassignUnsettled(after: index, lanes: lanes, spacing: spacing)
            }
        } else {
            lane = insert(index, lanes: lanes, mainLength: mainLength, spacing: spacing)
        }

        let position = assignedPosition[index] ?? 0
        let origin = cachedOrigin(lane: lane, position: position, spacing: spacing)

        if isAnchor {
            currentAnchorOrigin = origin
        }

        return (lane, origin)
    }

    private func insert(_ index: Int, lanes: Int, mainLength: Double, spacing: Double) -> Int {
        let lane = (0..<lanes).min { laneRunningTotal[$0] < laneRunningTotal[$1] } ?? 0
        assignedLane[index] = lane
        laneRunningTotal[lane] += mainLength + spacing

        let insertionPoint = laneIndices[lane].firstIndex { $0 > index } ?? laneIndices[lane].count
        laneIndices[lane].insert(index, at: insertionPoint)
        shiftPositions(lane: lane, from: insertionPoint)
        invalidateOrigins(lane: lane, fromPosition: insertionPoint)

        return lane
    }

    private func remove(_ index: Int, spacing: Double) {
        guard let lane = assignedLane[index], let position = assignedPosition[index] else { return }

        laneRunningTotal[lane] -= (lastKnownLength[index] ?? 0) + spacing
        laneIndices[lane].remove(at: position)
        assignedLane[index] = nil
        assignedPosition[index] = nil
        shiftPositions(lane: lane, from: position)
        invalidateOrigins(lane: lane, fromPosition: position)
    }

    /// A later item's lane was chosen from the lane totals at that moment,
    /// which included estimates for earlier items not measured yet. Once an
    /// earlier length changes, re-choose for every later item that hasn't
    /// been measured itself, so it doesn't stay stuck in a lane that only
    /// looked shortest because of a wrong guess.
    private func reassignUnsettled(after index: Int, lanes: Int, spacing: Double) {
        let candidates = assignedLane.keys.filter { $0 > index && !settledIndices.contains($0) }.sorted()
        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            remove(candidate, spacing: spacing)
        }

        for candidate in candidates {
            insert(candidate, lanes: lanes, mainLength: lastKnownLength[candidate] ?? 0, spacing: spacing)
        }
    }

    private func cachedOrigin(lane: Int, position: Int, spacing: Double) -> Double {
        while laneCachedOrigins[lane].count <= position {
            let i = laneCachedOrigins[lane].count
            let origin = i == 0
                ? 0
                : laneCachedOrigins[lane][i - 1] + (lastKnownLength[laneIndices[lane][i - 1]] ?? 0) + spacing
            laneCachedOrigins[lane].append(origin)
        }

        return laneCachedOrigins[lane][position]
    }

    /// `laneCachedOrigins[lane][p]` depends only on positions `0..<p`, so a
    /// changed position's own cached origin is still valid — only positions
    /// after it need dropping. An insert shifts everything from its own
    /// position onward, so that case invalidates starting there instead.
    private func invalidateOrigins(lane: Int, fromPosition position: Int) {
        guard position < laneCachedOrigins[lane].count else { return }

        laneCachedOrigins[lane].removeSubrange(position...)
    }

    private func shiftPositions(lane: Int, from insertionPoint: Int) {
        for position in insertionPoint..<laneIndices[lane].count {
            assignedPosition[laneIndices[lane][position]] = position
        }
    }
}
