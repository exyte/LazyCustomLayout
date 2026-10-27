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
/// re-placing the same subviews into different cells) — otherwise SwiftUI
/// tracks "whatever is at position N" instead of "this particular element",
/// and a reorder cross-dissolves instead of animating each element to its
/// new slot.
public struct LazyAnchoredScroll<Data: RandomAccessCollection, Layout: StreamingLayout, Content: View>: View where Data.Index == Int {
    var data: Data
    var axis: ScrollAxis
    var layout: Layout
    var estimatedItemLength: Double
    var bufferLength: Double?
    var maxLoadedItems: Int?
    var id: (Int, Data.Element) -> AnyHashable
    var content: (Data.Element) -> Content

    @State private var controller: LazyAnchoredScrollController<Layout>

    public init(
        _ data: Data,
        axis: ScrollAxis = .vertical,
        layout: Layout,
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
            layout: layout,
            estimatedItemLength: estimatedItemLength,
            bufferLength: bufferLength,
            maxLoadedItems: maxLoadedItems
        ))
    }

    public var body: some View {
        GeometryReader { proxy in
            let window = streamingLayoutWindow(
                anchor: controller.anchor,
                itemCount: data.count,
                axis: axis,
                viewportSize: proxy.size,
                bufferLength: bufferLength ?? (axis == .vertical ? proxy.size.height : proxy.size.width),
                maxLoadedItems: maxLoadedItems,
                estimatedItemLength: estimatedItemLength,
                sizeCache: controller.sizeCache,
                crossSizeCache: controller.crossSizeCache,
                layout: layout
            )

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
                ForEach(window.indices.map { WindowSlot(index: $0, id: id($0, data[$0])) }) { slot in
                    let index = slot.index

                    if let frame = window.frames[index], let proposal = window.proposals[index] {
                        // Two frames, not one: `proposal` leaves a dimension
                        // nil wherever the layout wants the item to size
                        // itself (e.g. a variable-width flow tag on its
                        // cross axis), so `.fixedSize` forces an ideal
                        // measurement for exactly those dimensions right
                        // after — a nil/nil `.frame` alone can't do this,
                        // since it has nothing of its own to redefine the
                        // proposal with, so it would otherwise just pass the
                        // *outer* `.frame(frame.width, frame.height)`'s
                        // proposal straight through instead of measuring an
                        // ideal size. `frame` is the walker's *previous*-render
                        // size for this item (real once measured, an estimate
                        // until then); it's reapplied after measuring so this
                        // item still lines up with where every other item was
                        // just placed, even during the one-render gap between
                        // an estimate and its real measurement. `.clipped()`
                        // absorbs that gap.
                        content(data[index])
                            .frame(width: proposal.width, height: proposal.height)
                            .fixedSize(horizontal: proposal.width == nil, vertical: proposal.height == nil)
                            .measuringSize { size in
                                controller.sizeCache[index] = axis == .vertical ? size.height : size.width
                                controller.crossSizeCache[index] = axis == .vertical ? size.width : size.height
                            }
                            .frame(width: frame.width, height: frame.height)
                            .clipped()
                            .offset(
                                x: frame.origin.x - (axis == .horizontal ? controller.anchor.offset + controller.overscrollOffset : 0),
                                y: frame.origin.y - (axis == .vertical ? controller.anchor.offset + controller.overscrollOffset : 0)
                            )
                    }
                }
            }
            // Same reasoning as the ZStack's own alignment above: must stay
            // top-leading regardless of axis, for the same reason.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onAppear { controller.viewportSize = proxy.size }
            .onChange(of: proxy.size) { _, newValue in controller.viewportSize = newValue }
            .gesture(ScrollDragGesture(
                onChanged: { controller.dragChanged($0) },
                onEnded: { controller.dragEnded($0) }
            ))
            .gesture(ScrollTouchDownGesture(onTouchDown: { controller.touchDown() }))
        }
    }
}

/// Carries a window index alongside whatever SwiftUI identity `id:` resolved
/// for it — `ForEach` needs `Identifiable` content to key by something other
/// than the index itself.
private struct WindowSlot: Identifiable {
    var index: Int
    var id: AnyHashable
}
