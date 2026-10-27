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

    private(set) var currentAnchorOrigin: Double = 0

    init(lanes: Int) {
        laneIndices = Array(repeating: [], count: lanes)
    }

    func position(
        for index: Int,
        isAnchor: Bool,
        lanes: Int,
        mainLength: Double,
        spacing: Double
    ) -> (lane: Int, origin: Double) {
        lastKnownLength[index] = mainLength

        let lane: Int
        if let existing = assignedLane[index] {
            lane = existing
        } else {
            lane = (0..<lanes).min { laneTotal($0, spacing: spacing) < laneTotal($1, spacing: spacing) } ?? 0
            assignedLane[index] = lane

            let insertionPoint = laneIndices[lane].firstIndex { $0 > index } ?? laneIndices[lane].count
            laneIndices[lane].insert(index, at: insertionPoint)
        }

        let origin = laneIndices[lane]
            .prefix { $0 < index }
            .reduce(0.0) { $0 + (lastKnownLength[$1] ?? 0) + spacing }

        if isAnchor {
            currentAnchorOrigin = origin
        }

        return (lane, origin)
    }

    private func laneTotal(_ lane: Int, spacing: Double) -> Double {
        laneIndices[lane].reduce(0.0) { $0 + (lastKnownLength[$1] ?? 0) + spacing }
    }
}
