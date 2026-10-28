import SwiftUI

/// Wraps variable-width items left-to-right (vertical axis) or top-to-bottom
/// (horizontal axis) — a tag cloud: each item sizes itself along the cross
/// axis, and a new line starts once the current one can't fit another item.
///
/// Every item proposes a nil cross length, i.e. "size yourself"; `place`
/// learns the real (or, for an unmeasured neighbor, estimated — see
/// `LazyAnchoredScrollController.crossSizeCache`) cross length from the
/// resulting `size` it's handed. That's the one piece a fixed-size layout
/// like the old revision of this type didn't need: `SizeCache` only ever
/// tracked a scroll-axis length per item, so a variable cross length had
/// nowhere to be remembered for an item outside the current window — see
/// `crossSizeCache` for how that gap was closed.
///
/// Which line an item belongs to can no longer be a pure function of its
/// index the way a fixed-width flow's was (`index / itemsPerLine`): it
/// depends on every earlier item's own cross length. `FlowPositions` works
/// this out with a greedy, CSS-flex-wrap-style forward sweep, continuing
/// from wherever the sweep last left off — the same "streamed one item at a
/// time" shape the rest of this package uses, not a full up-front pass.
///
/// Unlike `MasonryLayout`'s permanent lane choice, a line
/// assignment here is **not** permanent — it can't be: getting a lane
/// "wrong" just unbalances masonry's columns a little, but getting a line
/// "wrong" means packing more items onto it than actually fit, which
/// overflows the viewport, not just looks slightly uneven. Every first-seen
/// item starts out sized by a rough estimate (an average of whatever's
/// measured so far), so an early line is often built from guesses; once an
/// item's *real* cross length comes in and disagrees with the guess it was
/// placed with, the sweep rewinds to the start of that item's line and
/// replays forward from there with the now-better information, discarding
/// (and letting later calls rebuild) every line after it. This is bounded
/// work — only as far back as the one affected line, never all the way to
/// index 0 — and self-corrects fully within a render or two of a line
/// actually becoming visible, the same self-correcting spirit as every
/// other length this package tracks, just applied to line *membership*
/// instead of a single scalar.
///
/// What *does* still need remembering per call, the same as the old
/// fixed-width revision, is every line's own main-axis length (the tallest
/// item placed in it so far) — see `FlowPositions`.
public struct FlowLayout: StreamingLayout {
    public var spacing: Double
    public var lineSpacing: Double

    private let positions = FlowPositions()

    public init(spacing: Double = 8, lineSpacing: Double = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func proposedSize(context: StreamingLayoutContext, cache: inout Void) -> ProposedViewSize {
        ProposedViewSize(width: nil, height: nil)
    }

    public func place(size: CGSize, context: StreamingLayoutContext, cache: inout Void) -> CGRect {
        let totalCross = context.axis == .vertical ? context.viewportSize.width : context.viewportSize.height
        let mainLength = context.axis == .vertical ? size.height : size.width
        // Clamped: a single item wider than the whole container would
        // otherwise never fit any line, including one all by itself.
        let crossLength = min(context.axis == .vertical ? size.width : size.height, totalCross)

        let placement = positions.place(
            index: context.index,
            crossLength: crossLength,
            mainLength: mainLength,
            totalCross: totalCross,
            spacing: spacing,
            lineSpacing: lineSpacing,
            isAnchor: context.neighborFrame == nil
        )

        // Translate from the shared, anchor-independent coordinate space
        // into one where the *current* anchor sits at local origin 0 — see
        // `MasonryLayout.place` for the same translation and why
        // it's needed.
        let mainOrigin = placement.mainOrigin - positions.currentAnchorOrigin

        return frame(crossOrigin: placement.crossOrigin, mainOrigin: mainOrigin, size: size, context: context)
    }

    private func frame(crossOrigin: Double, mainOrigin: Double, size: CGSize, context: StreamingLayoutContext) -> CGRect {
        switch context.axis {
        case .vertical: return CGRect(x: crossOrigin, y: mainOrigin, width: size.width, height: size.height)
        case .horizontal: return CGRect(x: mainOrigin, y: crossOrigin, width: size.width, height: size.height)
        }
    }

    /// Everything on one line — the only sensible "natural" width for a
    /// flow with nothing constraining its cross axis.
    public func idealCrossLength(itemCrossLengths: [Double]) -> Double {
        guard !itemCrossLengths.isEmpty else { return 0 }

        return itemCrossLengths.reduce(0, +) + spacing * Double(itemCrossLengths.count - 1)
    }
}

/// Line membership (self-correcting, see `FlowLayout`'s doc) plus
/// each line's own main-axis length — the latter self-correcting the same
/// way `MasonryPositions`' main length is, never locked to a specific
/// numeric value, only recomputed from whatever's currently known or
/// estimated.
private final class FlowPositions {
    /// Each line's member indices, in increasing order — the greedy sweep
    /// below only ever appends to the most recent line or starts a new one,
    /// so this is sorted by construction, same as `MasonryPositions.laneIndices`.
    private var lineMembers: [[Int]] = []
    private var assignedLine: [Int: Int] = [:]
    private var lastKnownCrossLength: [Int: Double] = [:]
    private var lastKnownMainLength: [Int: Double] = [:]
    /// The highest index the sweep has ever reached — extending the sweep
    /// to a new index only ever needs to start here, never from 0.
    private var highestSweptIndex = -1
    /// Running origin of each line already resolved — truncated from
    /// whichever line the sweep just rewound to, or whose length changed,
    /// onward. Mirrors `GridRowLengths`' cache: summing every earlier
    /// line's length on every call made every walk slower the deeper into
    /// a long list it reached.
    private var cachedLineOrigins: [Double] = [0]

    /// The container cross length every line above was packed against — a
    /// rotation or resize invalidates all of them, since membership depends
    /// on how much fits.
    private var lastTotalCross: Double?

    private(set) var currentAnchorOrigin: Double = 0

    /// Drops line membership only; measured lengths stay, they're still
    /// right for a new container width.
    private func resetLines() {
        lineMembers = []
        assignedLine = [:]
        highestSweptIndex = -1
        cachedLineOrigins = [0]
    }

    func place(
        index: Int,
        crossLength: Double,
        mainLength: Double,
        totalCross: Double,
        spacing: Double,
        lineSpacing: Double,
        isAnchor: Bool
    ) -> (crossOrigin: Double, mainOrigin: Double) {
        if lastTotalCross != totalCross {
            resetLines()
            lastTotalCross = totalCross
        }

        let crossChanged = lastKnownCrossLength[index] != crossLength
        let mainChanged = lastKnownMainLength[index] != mainLength
        lastKnownCrossLength[index] = crossLength
        lastKnownMainLength[index] = mainLength

        if index > highestSweptIndex {
            sweep(from: highestSweptIndex + 1, through: index, totalCross: totalCross, spacing: spacing)
            highestSweptIndex = index
        } else if crossChanged, let line = assignedLine[index] {
            // This index's real cross length disagrees with whatever guess
            // its line was built from — rewind to that line's first member
            // and replay forward with the better information. Only this
            // line and everything after it can be wrong, since a line's
            // membership only ever depends on earlier items' lengths, never
            // later ones.
            let restartAt = lineMembers[line].first ?? index
            lineMembers.removeLast(lineMembers.count - line)
            for discarded in restartAt...highestSweptIndex { assignedLine[discarded] = nil }
            invalidateLineOrigins(from: line)
            sweep(from: restartAt, through: highestSweptIndex, totalCross: totalCross, spacing: spacing)
        } else if mainChanged, let line = assignedLine[index] {
            invalidateLineOrigins(from: line + 1)
        }

        let line = assignedLine[index] ?? 0
        let members = lineMembers[line]

        let crossOrigin = members
            .prefix { $0 < index }
            .reduce(0.0) { $0 + (lastKnownCrossLength[$1] ?? crossLength) + spacing }

        let mainOrigin = lineOrigin(line, lineSpacing: lineSpacing, fallback: mainLength)

        if isAnchor {
            currentAnchorOrigin = mainOrigin
        }

        return (crossOrigin, mainOrigin)
    }

    private func lineOrigin(_ line: Int, lineSpacing: Double, fallback: Double) -> Double {
        while cachedLineOrigins.count <= line {
            let previousLine = cachedLineOrigins.count - 1
            cachedLineOrigins.append(cachedLineOrigins[previousLine] + lineMainLength(previousLine, fallback: fallback) + lineSpacing)
        }

        return cachedLineOrigins[line]
    }

    /// `cachedLineOrigins[l]` depends only on lines `0..<l`, so a changed
    /// line's own cached origin is still valid — only lines after it need
    /// dropping. Index 0 is never dropped even when a rewind passes `line:
    /// 0`: it's the structural base case (sum over zero preceding lines is
    /// always 0), not a cached computation, and `lineOrigin`'s builder loop
    /// assumes it's always present.
    private func invalidateLineOrigins(from line: Int) {
        let keepFrom = max(line, 1)
        guard keepFrom < cachedLineOrigins.count else { return }

        cachedLineOrigins.removeSubrange(keepFrom...)
    }

    /// Extends the greedy sweep across `range`, joining each item onto the
    /// sweep's current line if it still fits — using whatever cross length
    /// is already known for every item in that line, or the running average
    /// of everything measured so far as the best available guess for one
    /// that isn't — otherwise starting a new line.
    private func sweep(from start: Int, through end: Int, totalCross: Double, spacing: Double) {
        guard start <= end else { return }

        if lineMembers.isEmpty {
            lineMembers = [[]]
        }

        for index in start...end {
            let cross = lastKnownCrossLength[index] ?? averageCrossLength
            var line = lineMembers.count - 1
            let used = lineMembers[line].reduce(0.0) { $0 + (lastKnownCrossLength[$1] ?? cross) + spacing }

            if !lineMembers[line].isEmpty && used + cross > totalCross {
                lineMembers.append([])
                line += 1
            }

            lineMembers[line].append(index)
            assignedLine[index] = line
        }
    }

    private var averageCrossLength: Double {
        let known = lastKnownCrossLength.values
        return known.isEmpty ? 0 : known.reduce(0, +) / Double(known.count)
    }

    private func lineMainLength(_ line: Int, fallback: Double) -> Double {
        guard line < lineMembers.count else { return fallback }

        return lineMembers[line].reduce(0.0) { max($0, lastKnownMainLength[$1] ?? fallback) }
    }
}
