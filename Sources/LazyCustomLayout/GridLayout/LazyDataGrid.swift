import SwiftUI

/// The data-driven counterpart to `LazyGrid`'s `@ViewBuilder` inits — same
/// `GridLayout`/`GridPlacement` auto-placement, but fed directly from a
/// `RandomAccessCollection` + a plain `content` closure instead of slicing
/// a `Group(subviews:)` tree, the same way `LazyFlow`/`LazyMasonry`/
/// `LazyStack` are each a direct data-driven front onto their own layout.
///
/// Reach for this one when the data is already a collection of model
/// values (e.g. a photo feed) rather than fixed SwiftUI content; reach for
/// `LazyGrid` when starting from a `@ViewBuilder` tree instead. Both get
/// `LazyAnchoredScroll`'s default cell reuse, and passing a stable `id:`
/// keeps a `gridSpan`/track-count move animating to its new cell instead of
/// cross-dissolving — see `ReusePool`'s doc comment.
///
/// Sizes itself along the scroll axis per `.lazyLayoutSizing(_:)` — hugs
/// content up to the offered space and scrolls beyond it by default.
public struct LazyDataGrid<Data: RandomAccessCollection, Content: View>: View where Data.Index == Int {
    var data: Data
    var axis: ScrollAxis
    var tracks: [GridTrack]
    var spacing: Double
    var packing: GridPacking
    var estimatedMainLength: Double
    var span: (Data.Element) -> GridSpan
    var id: (Int, Data.Element) -> AnyHashable
    var content: (Data.Element) -> Content

    public init(
        _ data: Data,
        columns: Int,
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedRowLength: Double = 100,
        span: @escaping (Data.Element) -> GridSpan = { _ in GridSpan() },
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, axis: .vertical, tracks: Self.equalTracks(columns), spacing: spacing, packing: packing, estimatedMainLength: estimatedRowLength, span: span, id: id, content: content)
    }

    public init(
        _ data: Data,
        columns: [GridTrack],
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedRowLength: Double = 100,
        span: @escaping (Data.Element) -> GridSpan = { _ in GridSpan() },
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, axis: .vertical, tracks: columns, spacing: spacing, packing: packing, estimatedMainLength: estimatedRowLength, span: span, id: id, content: content)
    }

    public init(
        _ data: Data,
        rows: Int,
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedColumnLength: Double = 100,
        span: @escaping (Data.Element) -> GridSpan = { _ in GridSpan() },
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, axis: .horizontal, tracks: Self.equalTracks(rows), spacing: spacing, packing: packing, estimatedMainLength: estimatedColumnLength, span: span, id: id, content: content)
    }

    public init(
        _ data: Data,
        rows: [GridTrack],
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedColumnLength: Double = 100,
        span: @escaping (Data.Element) -> GridSpan = { _ in GridSpan() },
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, axis: .horizontal, tracks: rows, spacing: spacing, packing: packing, estimatedMainLength: estimatedColumnLength, span: span, id: id, content: content)
    }

    private init(
        _ data: Data,
        axis: ScrollAxis,
        tracks: [GridTrack],
        spacing: Double,
        packing: GridPacking,
        estimatedMainLength: Double,
        span: @escaping (Data.Element) -> GridSpan,
        id: @escaping (Int, Data.Element) -> AnyHashable,
        content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.axis = axis
        self.tracks = tracks
        self.spacing = spacing
        self.packing = packing
        self.estimatedMainLength = estimatedMainLength
        self.span = span
        self.id = id
        self.content = content
    }

    private static func equalTracks(_ count: Int) -> [GridTrack] {
        Array(repeating: .fr(1), count: max(1, count))
    }

    public var body: some View {
        LazyAnchoredScroll(
            data,
            axis: axis,
            layout: GridLayout(
                tracks: tracks,
                axis: axis,
                packing: packing,
                spacing: spacing,
                lineSpacing: spacing,
                estimatedMainLength: estimatedMainLength,
                spans: data.map(span)
            ),
            estimatedItemLength: estimatedMainLength,
            id: id,
            content: content
        )
    }
}
