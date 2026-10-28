import SwiftUI

/// Which way an item is being placed relative to the anchor: `.forward`
/// walks toward higher indices (revealing more content ahead), `.backward`
/// toward lower ones.
public enum StreamingLayoutDirection {
    case forward
    case backward
}

/// Everything a `StreamingLayout` might need to place one item — mirrors
/// what SwiftUI's `Layout` gets via `bounds`/`proposal`/`subviews`, but for a
/// single streamed item instead of the whole collection at once.
public struct StreamingLayoutContext {
    public var axis: ScrollAxis
    public var direction: StreamingLayoutDirection
    public var index: Int
    public var itemCount: Int
    public var anchor: ScrollAnchor<Int>
    public var viewportSize: CGSize
    /// The already-placed neighbor immediately on the side `direction` is
    /// walking away from — `nil` for the anchor item itself, which has none.
    public var neighborFrame: CGRect?

    public init(
        axis: ScrollAxis,
        direction: StreamingLayoutDirection,
        index: Int,
        itemCount: Int,
        anchor: ScrollAnchor<Int>,
        viewportSize: CGSize,
        neighborFrame: CGRect?
    ) {
        self.axis = axis
        self.direction = direction
        self.index = index
        self.itemCount = itemCount
        self.anchor = anchor
        self.viewportSize = viewportSize
        self.neighborFrame = neighborFrame
    }

    /// Proposes the full cross-axis length, leaving the scroll axis
    /// unconstrained — the common case for layouts where every item spans
    /// the full width (vertical) or full height (horizontal) and sizes
    /// itself naturally along the scroll axis, like `StackLayout`.
    /// Not universal: a layout that gives each item only part of the
    /// cross-axis (columns, flow) needs its own `proposedSize` instead.
    public var fullCrossAxisProposal: ProposedViewSize {
        switch axis {
        case .vertical: ProposedViewSize(width: viewportSize.width, height: nil)
        case .horizontal: ProposedViewSize(width: nil, height: viewportSize.height)
        }
    }
}

/// Lays out items streamed in one at a time, forward or backward from an
/// anchor, the same propose-then-place shape as SwiftUI's `Layout` protocol:
/// `proposedSize` is asked what to propose when measuring an item (like
/// `Layout.sizeThatFits`/`LayoutSubview.sizeThatFits(_:)`), then `place` is
/// handed the item's real resulting size and returns its frame (like
/// `LayoutSubview.place`, but returning the frame instead of applying it,
/// since nothing may be rendered yet when a lazy container is only
/// window-planning, not placing real subviews).
///
/// The difference from `Layout` is being streamed: instead of being handed
/// every subview at once, a conformer only ever sees one item plus its
/// already-placed neighbor — never the full set — so a lazy container built
/// on top never needs to measure more than a small window.
///
/// `Cache` mirrors `Layout.Cache`, but doesn't need `updateCache`: a window
/// is always walked fresh from the anchor outward, never incrementally
/// updated, so there's nothing to keep a long-lived cache in sync with.
///
/// Built-in conformers: `StackLayout`, `MasonryLayout`, `FlowLayout`, `GridLayout`.
public protocol StreamingLayout {
    associatedtype Cache = Void

    func makeCache() -> Cache

    /// The size to propose when measuring the item described by `context`.
    func proposedSize(context: StreamingLayoutContext, cache: inout Cache) -> ProposedViewSize

    /// The item's frame, given `size` — its real response to `proposedSize`
    /// once actually measured, or an estimate while only window-planning.
    func place(size: CGSize, context: StreamingLayoutContext, cache: inout Cache) -> CGRect

    /// The cross-axis length to lay out against when nothing proposes one —
    /// used by `EagerStreamingLayout` (backing `.fitToContent` sizing) when
    /// its own parent proposes no width (vertical axis) or height
    /// (horizontal axis) of its own. `itemCrossLengths` is every item's own
    /// ideal, `.unspecified`-proposed cross length, in index order.
    /// Default: the widest item, correct for a single-column layout like
    /// `StackLayout`.
    func idealCrossLength(itemCrossLengths: [Double]) -> Double
}

extension StreamingLayout where Cache == Void {
    public func makeCache() {}
}

extension StreamingLayout {
    public func idealCrossLength(itemCrossLengths: [Double]) -> Double {
        itemCrossLengths.max() ?? 0
    }
}
