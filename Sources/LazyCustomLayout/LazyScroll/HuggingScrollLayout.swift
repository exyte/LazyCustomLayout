import SwiftUI

/// Wraps a single child, reporting `min(proposal, mainLength)` along `axis`'s
/// main dimension instead of the child's own `sizeThatFits` — backs
/// `LazyAnchoredScroll`'s `.scroll` sizing. Its inner `GeometryReader`-based
/// scroll body always fills whatever it's proposed (that's how it decides
/// its own viewport), so without this wrapper, `.scroll` could only ever
/// greedily fill space, same as `.scrollFillingSpace`.
///
/// `mainLength` is the walker's own self-correcting best estimate of the
/// full content length — real once the window has reached both true edges,
/// an estimate otherwise — so the reported size converges within a render or
/// two, the same spirit as every other length this package tracks.
struct HuggingScrollLayout: SwiftUI.Layout {
    var axis: ScrollAxis
    var mainLength: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let proposedMain = axis == .vertical ? proposal.height : proposal.width
        let proposedCross = axis == .vertical ? proposal.width : proposal.height
        let resolvedMain = min(proposedMain ?? .infinity, mainLength)

        switch axis {
        case .vertical: return CGSize(width: proposedCross ?? resolvedMain, height: resolvedMain)
        case .horizontal: return CGSize(width: resolvedMain, height: proposedCross ?? resolvedMain)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
