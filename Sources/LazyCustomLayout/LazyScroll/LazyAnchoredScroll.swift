import SwiftUI

/// A lazily-loaded, anchor-positioned scroll container: only a window of
/// items around the current anchor is ever instantiated, measured, and
/// placed via `layout`, so content never needs an upfront total size the
/// way `UIScrollView`-backed containers do. How far that window reaches is
/// `bufferLength` (points past the viewport, each direction; `nil` means one
/// extra viewport) and/or `maxLoadedItems` (a hard cap on item count,
/// regardless of distance) — whichever limit is hit first wins.
///
/// For a `RandomAccessCollection` rendered through a `StreamingLayout`. For
/// one eagerly-rendered piece of content with nothing to window, reach for
/// `AnchoredScrollView` instead.
///
/// Items are identified by their index into `data` by default, not a stable
/// id of their own — fine for a fixed-size table like this one, but revisit
/// once inserting/removing items while scrolled needs the no-jump guarantee
/// the anchor model was built for. Pass `id:` when `data`'s own order can
/// change without the elements themselves changing identity (e.g. `LazyGrid`
/// re-placing the same subviews into different cells): `ReusePool` keys its
/// slots by that id, so the same element keeps its slot — and therefore its
/// SwiftUI identity — as it moves to a new index, letting the move animate
/// instead of cross-dissolving. The default index-based `id:` just means a
/// slot is keyed by "whatever is at position N" instead.
///
/// Reuses a stable pool of cell identities by default — see `ReusePool` and
/// `View.cellReuse(_:)` — so a cell's own local `@State` survives being
/// rebound to a different item as the window moves, the same caveat a
/// `UITableViewCell` has. Derive per-item state from the bound item itself,
/// or reset it via `.onChange(of:)`, rather than assuming a fresh `@State`
/// per item.
///
/// Sizes itself along `axis` per `.lazyLayoutSizing(_:)` — hugs content up
/// to the offered space and scrolls beyond it by default (`.scroll`), with
/// `.fitToContent` (eager, non-scrolling) and `.scrollFillingSpace` (always
/// greedy) also available. See `LazyLayoutSizing`.
public struct LazyAnchoredScroll<Data: RandomAccessCollection, Layout: StreamingLayout, Content: View>: View where Data.Index == Int {
    var data: Data
    var axis: ScrollAxis
    /// Called fresh wherever a brand-new, un-shared layout instance is
    /// needed — see `EagerStreamingLayout`'s own doc for why `.fitToContent`
    /// sizing can't reuse `controller`'s single long-lived instance the way
    /// `.scroll`/`.scrollFillingSpace` do.
    var layout: () -> Layout
    var estimatedItemLength: Double
    var bufferLength: Double?
    var maxLoadedItems: Int?
    var id: (Int, Data.Element) -> AnyHashable
    var content: (Data.Element) -> Content

    @Environment(\.cellReuseEnabled) var cellReuseEnabled
    @Environment(\.lazyLayoutSizing) var sizing

    @State private var controller: LazyAnchoredScrollController<Layout>
    @State private var reusePool = ReusePool()

    public init(
        _ data: Data,
        axis: ScrollAxis = .vertical,
        layout: @autoclosure @escaping () -> Layout,
        estimatedItemLength: Double,
        bufferLength: Double? = nil,
        maxLoadedItems: Int? = nil,
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.axis = axis
        self.layout = layout
        self.estimatedItemLength = estimatedItemLength
        self.bufferLength = bufferLength
        self.maxLoadedItems = maxLoadedItems
        self.id = id
        self.content = content
        _controller = State(initialValue: LazyAnchoredScrollController(
            axis: axis,
            itemCount: data.count,
            layout: layout(),
            estimatedItemLength: estimatedItemLength,
            bufferLength: bufferLength,
            maxLoadedItems: maxLoadedItems
        ))
    }

    public var body: some View {
        let _ = ScrollPerfLog.shared.recordBodyPass()

        switch sizing {
        case .fitToContent: eagerContent
        case .scrollFillingSpace: scrollContent
        case .scroll: HuggingScrollLayout(axis: axis, mainLength: hugLength) { scrollContent }
        }
    }

    /// The walker's own self-correcting best estimate of the full content
    /// length once `.scroll` sizing needs one of its own (before the window
    /// has ever reached both true edges to measure it for real) — not
    /// reused across layouts the way `StreamingLayoutWalker`'s own
    /// estimate-until-measured fallback is, since this estimate covers the
    /// *whole* collection rather than one item at a time, and a layout that
    /// packs several items per line (flow, grid, masonry) would otherwise
    /// read as far too long.
    private var hugLength: Double {
        controller.knownContentLength ?? Double(data.count) * (controller.sizeCache.averageSize ?? estimatedItemLength)
    }

    @ViewBuilder
    private var eagerContent: some View {
        EagerStreamingLayout(axis: axis, makeLayout: layout) {
            ForEach(data.indices.map { WindowSlot(index: $0, id: id($0, data[$0])) }) { slot in
                content(data[slot.index])
            }
        }
    }

    private var scrollContent: some View {
        GeometryReader { proxy in
            let window = controller.currentWindow(itemCount: data.count, viewportSize: proxy.size)

            // Always top-leading, regardless of axis: every child is placed
            // with an explicit `.offset`, which — unlike `.position` — never
            // feeds back into this ZStack's own computed size, so the
            // ZStack's "natural" size here is just the union of children's
            // un-offset frames (one item's worth), not the full laid-out
            // content. Any alignment with a non-leading/non-top component
            // would then center (or trail) that undersized natural content
            // within the `.frame` below, shifting every offset by the same
            // amount — for a horizontal axis, `.leading`'s vertical `.center`
            // component did exactly this, shifting rows down far enough that
            // `.clipped()` cut the last one off entirely.
            ZStack(alignment: .topLeading) {
                if cellReuseEnabled {
                    let _ = reusePool.assign(items: window.indices.map { (index: $0, id: id($0, data[$0])) })
                    let _ = ScrollPerfLog.shared.recordState(
                        anchorID: controller.anchor.id,
                        anchorOffset: controller.anchor.offset,
                        windowIndexCount: window.indices.count,
                        poolSlotCount: reusePool.slots.count,
                        poolActiveCount: reusePool.slots.filter { reusePool.isActive(slot: $0) }.count,
                        forwardSlack: window.forwardSlack,
                        backwardSlack: window.backwardSlack,
                        viewportSize: proxy.size,
                        sampleFrame: window.indices.first.flatMap { window.frames[$0] },
                        sampleProposal: window.indices.first.flatMap { window.proposals[$0] }
                    )

                    ForEach(reusePool.slots, id: \.self) { slot in
                        let index = reusePool.index(forSlot: slot)

                        if reusePool.isActive(slot: slot), let frame = window.frames[index], let proposal = window.proposals[index] {
                            cell(index: index, frame: frame, proposal: proposal)
                        } else {
                            // An idle slot: its last-bound index scrolled out
                            // and nothing has taken the slot yet. Kept in the
                            // tree (not removed with `if`) so the next item
                            // that takes it is a content update to an
                            // already-mounted identity, not a fresh insert —
                            // the whole point of reuse. No frame/proposal to
                            // size it by, since `window` has nothing for an
                            // index that isn't currently visible, and no
                            // measuring, since writing a stale index's size
                            // into the caches would corrupt them.
                            content(data[index])
                                .frame(width: 0, height: 0)
                                .clipped()
                                .opacity(0)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                } else {
                    ForEach(window.indices.map { WindowSlot(index: $0, id: id($0, data[$0])) }) { slot in
                        let index = slot.index

                        if let frame = window.frames[index], let proposal = window.proposals[index] {
                            cell(index: index, frame: frame, proposal: proposal)
                        }
                    }
                }
            }
            // The anchor/overscroll shift used to be baked into every
            // child's own `.offset` above, so scrolling touched N offset
            // modifiers a frame instead of one — a child's `frame.origin`
            // only changes when the window itself shifts (a different
            // anchor, a remeasured item), not on every scroll tick, so
            // hoisting the shift here means the common case (same window,
            // new anchor offset) updates a single modifier instead of N.
            .offset(
                x: axis == .horizontal ? -(controller.anchor.offset + controller.overscrollOffset) : 0,
                y: axis == .vertical ? -(controller.anchor.offset + controller.overscrollOffset) : 0
            )
            // Same reasoning as the ZStack's own alignment above: must stay
            // top-leading regardless of axis, for the same reason.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                controller.viewportSize = proxy.size
                controller.sizing = sizing
            }
            .onChange(of: proxy.size) { _, newValue in controller.viewportSize = newValue }
            .onChange(of: sizing) { _, newValue in controller.sizing = newValue }
            .gesture(ScrollDragGesture(
                onChanged: { controller.dragChanged($0) },
                onEnded: { controller.dragEnded($0) }
            ))
            .gesture(ScrollTouchDownGesture(onTouchDown: { controller.touchDown() }))
        }
    }

    // Two frames, not one: `proposal` leaves a dimension nil wherever the
    // layout wants the item to size itself (e.g. a variable-width flow tag
    // on its cross axis), so `.fixedSize` forces an ideal measurement for
    // exactly those dimensions right after — a nil/nil `.frame` alone can't
    // do this, since it has nothing of its own to redefine the proposal
    // with, so it would otherwise just pass the *outer*
    // `.frame(frame.width, frame.height)`'s proposal straight through
    // instead of measuring an ideal size. `frame` is the walker's
    // *previous*-render size for this item (real once measured, an estimate
    // until then); it's reapplied after measuring so this item still lines
    // up with where every other item was just placed, even during the
    // one-render gap between an estimate and its real measurement.
    // `.clipped()` absorbs that gap.
    @ViewBuilder
    private func cell(index: Int, frame: CGRect, proposal: ProposedViewSize) -> some View {
        content(data[index])
            .frame(width: proposal.width, height: proposal.height)
            .fixedSize(horizontal: proposal.width == nil, vertical: proposal.height == nil)
            .measuringSize(key: index) { size in
                controller.sizeCache[index] = axis == .vertical ? size.height : size.width
                controller.crossSizeCache[index] = axis == .vertical ? size.width : size.height
            }
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .offset(x: frame.origin.x, y: frame.origin.y)
    }
}

/// Carries a window index alongside whatever SwiftUI identity `id:` resolved
/// for it — `ForEach` needs `Identifiable` content to key by something other
/// than the index itself.
private struct WindowSlot: Identifiable {
    var index: Int
    var id: AnyHashable
}
