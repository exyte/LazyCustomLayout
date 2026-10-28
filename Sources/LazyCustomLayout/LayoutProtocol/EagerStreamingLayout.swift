import SwiftUI

/// Drives any `StreamingLayout` eagerly: every subview is measured and
/// placed in one pass through the same placement math the lazy, windowed
/// path uses (`FlowPositions`, `GridRowLengths`, masonry's lane picker,
/// ...), so wrap/grid placement logic never needs writing twice. Backs
/// `LazyAnchoredScroll`'s `.fitToContent` sizing — nothing here is
/// virtualized, so only reach for it with content genuinely small enough to
/// render in full.
struct EagerStreamingLayout<L: StreamingLayout>: SwiftUI.Layout {
    var axis: ScrollAxis
    /// Called fresh on every `sizeThatFits`/`placeSubviews` — never once and
    /// reused — because every built-in `StreamingLayout` keeps its
    /// line/row/lane bookkeeping in a reference type created at `init` (see
    /// e.g. `FlowLayout.positions`), assuming one fixed cross length across
    /// the whole walk. SwiftUI probes `sizeThatFits` at several candidate
    /// widths before committing to one via `placeSubviews`; reusing one
    /// instance across those probes would let an earlier, narrower probe's
    /// line/row assignments leak into a later, wider one's.
    var makeLayout: () -> L

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let viewportSize = resolvedViewportSize(proposal: proposal, subviews: subviews)
        let frames = walk(subviews: subviews, viewportSize: viewportSize)
        let mainExtent = frames.map { axis == .vertical ? $0.maxY : $0.maxX }.max() ?? 0
        let crossLength = axis == .vertical ? viewportSize.width : viewportSize.height

        switch axis {
        case .vertical: return CGSize(width: crossLength, height: mainExtent)
        case .horizontal: return CGSize(width: mainExtent, height: crossLength)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let viewportSize = resolvedViewportSize(proposal: proposal, subviews: subviews)
        let frames = walk(subviews: subviews, viewportSize: viewportSize)

        for (index, subview) in subviews.enumerated() {
            let frame = frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// The cross length every item is walked against — the proposal's own,
    /// when given one, otherwise `idealCrossLength` fed by every item's own
    /// `.unspecified`-measured size. The main axis is always `.infinity`:
    /// nothing here is windowed, so there's no viewport length to reach
    /// toward and stop at.
    private func resolvedViewportSize(proposal: ProposedViewSize, subviews: Subviews) -> CGSize {
        let proposedCross = axis == .vertical ? proposal.width : proposal.height

        let crossLength = proposedCross ?? {
            let itemCrossLengths = subviews.map { subview -> Double in
                let size = subview.sizeThatFits(.unspecified)
                return axis == .vertical ? size.width : size.height
            }
            return makeLayout().idealCrossLength(itemCrossLengths: itemCrossLengths)
        }()

        switch axis {
        case .vertical: return CGSize(width: crossLength, height: .infinity)
        case .horizontal: return CGSize(width: .infinity, height: crossLength)
        }
    }

    private func walk(subviews: Subviews, viewportSize: CGSize) -> [CGRect] {
        eagerStreamingFrames(axis: axis, itemCount: subviews.count, viewportSize: viewportSize, layout: makeLayout()) { index, proposal in
            subviews[index].sizeThatFits(proposal)
        }
    }
}

/// The pure placement core behind `EagerStreamingLayout`: every index from
/// `0..<itemCount` measured and placed in one forward pass through `layout`,
/// the same `StreamingLayoutContext`-driven propose-then-place shape
/// `streamingLayoutWindow` uses for the lazy, windowed path — just never
/// stopping partway through a window. Free of SwiftUI's `Subviews`/
/// `LayoutSubview`, so it's directly testable with a plain `measure`
/// closure, the same way `streamingLayoutWindow` is tested through fixed
/// `SizeCache` values instead of real views.
func eagerStreamingFrames<L: StreamingLayout>(
    axis: ScrollAxis,
    itemCount: Int,
    viewportSize: CGSize,
    layout: L,
    measure: (Int, ProposedViewSize) -> CGSize
) -> [CGRect] {
    var cache = layout.makeCache()
    var neighborFrame: CGRect?
    var frames: [CGRect] = []

    for index in 0..<itemCount {
        let context = StreamingLayoutContext(
            axis: axis,
            direction: .forward,
            index: index,
            itemCount: itemCount,
            anchor: ScrollAnchor(id: 0),
            viewportSize: viewportSize,
            neighborFrame: neighborFrame
        )
        let proposedSize = layout.proposedSize(context: context, cache: &cache)
        let measuredSize = measure(index, proposedSize)
        let frame = layout.place(size: measuredSize, context: context, cache: &cache)
        frames.append(frame)
        neighborFrame = frame
    }

    return frames
}
