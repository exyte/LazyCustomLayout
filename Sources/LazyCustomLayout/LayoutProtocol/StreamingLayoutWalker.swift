import SwiftUI

/// The result of walking a `StreamingLayout` outward from an anchor: which
/// indices to render, their frames and proposals (in the anchor's local
/// coordinate space), and — only when the walk actually reaches that true
/// edge within the buffered distance or item cap — the slack in each
/// direction for rubber-banding.
struct StreamingLayoutWindow {
    var indices: [Int]
    var frames: [Int: CGRect]
    var proposals: [Int: ProposedViewSize]
    var forwardSlack: Double?
    var backwardSlack: Double?
}

/// Walks `layout` forward and backward from `anchor`, as far as
/// `viewportLength + bufferLength` needs in each direction (and no more than
/// `maxLoadedItems` items total, if given — the caller's control over how
/// much stays in memory), using measured sizes from `sizeCache` where
/// available and an estimate (`sizeCache`'s own running average, falling
/// back to `estimatedItemLength`) for anything not yet measured. Called
/// fresh on every layout pass and every slack query — it's a pure function
/// of its inputs, so there's nothing to keep in sync.
@MainActor
func streamingLayoutWindow<Layout: StreamingLayout>(
    anchor: ScrollAnchor<Int>,
    itemCount: Int,
    axis: ScrollAxis,
    viewportSize: CGSize,
    bufferLength: Double,
    maxLoadedItems: Int?,
    estimatedItemLength: Double,
    sizeCache: SizeCache<Int>,
    crossSizeCache: SizeCache<Int>,
    layout: Layout
) -> StreamingLayoutWindow {
    guard itemCount > 0 else {
        return StreamingLayoutWindow(indices: [], frames: [:], proposals: [:], forwardSlack: 0, backwardSlack: 0)
    }

    let viewportLength = axis == .vertical ? viewportSize.height : viewportSize.width
    let reach = viewportLength + bufferLength

    func axisOrigin(_ rect: CGRect) -> Double { axis == .vertical ? rect.minY : rect.minX }
    func axisEnd(_ rect: CGRect) -> Double { axis == .vertical ? rect.maxY : rect.maxX }

    func resolvedSize(for index: Int, proposal: ProposedViewSize) -> CGSize {
        let length = sizeCache[index] ?? sizeCache.averageSize ?? estimatedItemLength
        // Only consulted when a layout proposes a nil cross length, meaning
        // it wants the item to size itself (e.g. a variable-width flow tag)
        // — every other conformer proposes a fixed cross length and never
        // reaches this fallback chain.
        let crossLength = crossSizeCache[index] ?? crossSizeCache.averageSize ?? estimatedItemLength

        switch axis {
        case .vertical: return CGSize(width: proposal.width ?? crossLength, height: length)
        case .horizontal: return CGSize(width: length, height: proposal.height ?? crossLength)
        }
    }

    func place(
        index: Int,
        direction: StreamingLayoutDirection,
        neighborFrame: CGRect?,
        cache: inout Layout.Cache
    ) -> (frame: CGRect, proposal: ProposedViewSize) {
        let context = StreamingLayoutContext(
            axis: axis,
            direction: direction,
            index: index,
            itemCount: itemCount,
            anchor: anchor,
            viewportSize: viewportSize,
            neighborFrame: neighborFrame
        )
        let proposal = layout.proposedSize(context: context, cache: &cache)
        let size = resolvedSize(for: index, proposal: proposal)
        return (layout.place(size: size, context: context, cache: &cache), proposal)
    }

    var cache = layout.makeCache()
    var frames: [Int: CGRect] = [:]
    var proposals: [Int: ProposedViewSize] = [:]
    var indices: [Int] = [anchor.id]

    let anchorPlacement = place(index: anchor.id, direction: .forward, neighborFrame: nil, cache: &cache)
    frames[anchor.id] = anchorPlacement.frame
    proposals[anchor.id] = anchorPlacement.proposal

    // MARK: Forward

    var forwardCache = cache
    var forwardSlack: Double?
    var currentFrame = anchorPlacement.frame
    var index = anchor.id
    var loadedCount = 1

    while true {
        if index == itemCount - 1 {
            forwardSlack = max(0, (axisEnd(currentFrame) - anchor.offset) - viewportLength)
            break
        }
        if axisEnd(currentFrame) - anchor.offset >= reach {
            break
        }
        if let maxLoadedItems, loadedCount >= maxLoadedItems {
            break
        }

        index += 1
        let placement = place(index: index, direction: .forward, neighborFrame: currentFrame, cache: &forwardCache)
        frames[index] = placement.frame
        proposals[index] = placement.proposal
        indices.append(index)
        currentFrame = placement.frame
        loadedCount += 1
    }

    // MARK: Backward

    // A fresh cache, not a clone of the post-anchor forward one: nothing
    // before the anchor is constrained by what's after it (a masonry lane
    // the anchor just occupied going forward is still free going backward;
    // a flow line the anchor just filled didn't exist yet before it). Which
    // also means a multi-item-wide anchor "row"/"lane" can't be reconstructed
    // backward from a single item — see `MasonryLayout` and
    // `FlowLayout`'s docs for the resulting, accepted seam right at
    // the anchor boundary.
    var backwardCache = layout.makeCache()
    var backwardSlack: Double?
    currentFrame = anchorPlacement.frame
    index = anchor.id

    while true {
        if index == 0 {
            backwardSlack = max(0, anchor.offset - axisOrigin(currentFrame))
            break
        }
        if axisOrigin(currentFrame) - anchor.offset <= -bufferLength {
            break
        }
        if let maxLoadedItems, loadedCount >= maxLoadedItems {
            break
        }

        index -= 1
        let placement = place(index: index, direction: .backward, neighborFrame: currentFrame, cache: &backwardCache)
        frames[index] = placement.frame
        proposals[index] = placement.proposal
        indices.append(index)
        currentFrame = placement.frame
        loadedCount += 1
    }

    return StreamingLayoutWindow(indices: indices, frames: frames, proposals: proposals, forwardSlack: forwardSlack, backwardSlack: backwardSlack)
}
