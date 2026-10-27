import SwiftUI

/// A CSS-Grid-style container: give it a column or row count (or an
/// explicit track list mixing fixed `.px` and proportional `.fr` lengths)
/// and it auto-places whatever content you hand it, one cell — or several,
/// via `.gridSpan(column:row:)` — at a time.
///
/// Which argument you pass decides how it behaves:
/// - `columns:` alone scrolls vertically; rows size to their own content.
/// - `rows:` alone scrolls horizontally; columns size to their own content.
/// - Both together make a fixed grid that fills whatever space it's given
///   on both axes and never scrolls, since there's nothing left to stream.
///
/// The scrolling cases are built on `LazyAnchoredScroll` + `GridLayout`,
/// so only the window of cells actually on screen is ever instantiated.
/// Every case shares the same `GridPlacement` auto-placement engine, since
/// where an item's cell goes never depends on its measured size — only
/// track *lengths* do, which is why only those need `LazyAnchoredScroll`'s
/// streaming at all.
public struct LazyGrid<Content: View>: View {
    var columns: [GridTrack]?
    var rows: [GridTrack]?
    var spacing: Double
    var packing: GridPacking
    var estimatedMainLength: Double
    var content: Content

    public init(
        columns: Int,
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedRowLength: Double = 100,
        @ViewBuilder content: () -> Content
    ) {
        self.init(columns: Self.equalTracks(columns), rows: nil, spacing: spacing, packing: packing, estimatedMainLength: estimatedRowLength, content: content())
    }

    public init(
        columns: [GridTrack],
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedRowLength: Double = 100,
        @ViewBuilder content: () -> Content
    ) {
        self.init(columns: columns, rows: nil, spacing: spacing, packing: packing, estimatedMainLength: estimatedRowLength, content: content())
    }

    public init(
        rows: Int,
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedColumnLength: Double = 100,
        @ViewBuilder content: () -> Content
    ) {
        self.init(columns: nil, rows: Self.equalTracks(rows), spacing: spacing, packing: packing, estimatedMainLength: estimatedColumnLength, content: content())
    }

    public init(
        rows: [GridTrack],
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        estimatedColumnLength: Double = 100,
        @ViewBuilder content: () -> Content
    ) {
        self.init(columns: nil, rows: rows, spacing: spacing, packing: packing, estimatedMainLength: estimatedColumnLength, content: content())
    }

    /// Both given at once: a fixed grid, sized against whatever space it's
    /// given on both axes, never scrolling.
    public init(
        columns: Int,
        rows: Int,
        spacing: Double = 8,
        packing: GridPacking = .sparse,
        @ViewBuilder content: () -> Content
    ) {
        self.init(columns: Self.equalTracks(columns), rows: Self.equalTracks(rows), spacing: spacing, packing: packing, estimatedMainLength: 0, content: content())
    }

    private init(columns: [GridTrack]?, rows: [GridTrack]?, spacing: Double, packing: GridPacking, estimatedMainLength: Double, content: Content) {
        self.columns = columns
        self.rows = rows
        self.spacing = spacing
        self.packing = packing
        self.estimatedMainLength = estimatedMainLength
        self.content = content
    }

    private static func equalTracks(_ count: Int) -> [GridTrack] {
        Array(repeating: .fr(1), count: max(1, count))
    }

    public var body: some View {
        Group(subviews: content) { subviews in
            let items = Array(subviews)

            if let columns, let rows {
                FixedGrid(items: items, columns: columns, rows: rows, packing: packing, spacing: spacing)
            } else if let columns {
                scrollingGrid(tracks: columns, axis: .vertical, items: items)
            } else if let rows {
                scrollingGrid(tracks: rows, axis: .horizontal, items: items)
            }
        }
    }

    private func scrollingGrid(tracks: [GridTrack], axis: ScrollAxis, items: [Subview]) -> some View {
        LazyAnchoredScroll(
            items,
            axis: axis,
            layout: GridLayout(
                tracks: tracks,
                axis: axis,
                packing: packing,
                spacing: spacing,
                lineSpacing: spacing,
                estimatedMainLength: estimatedMainLength,
                spans: items.map { $0.containerValues.gridSpan }
            ),
            estimatedItemLength: estimatedMainLength,
            id: { _, item in item.id }
        ) { item in item }
    }
}

/// The non-scrolling case: every item is always on screen, so there's
/// nothing to stream — just resolve both axes' tracks against the space
/// `proxy` gives us and place every item directly, the same way
/// `CalculatorExample`'s hand-built layout already did before moving onto
/// this type.
private struct FixedGrid: View {
    var items: [Subview]
    var columns: [GridTrack]
    var rows: [GridTrack]
    var packing: GridPacking
    var spacing: Double

    var body: some View {
        GeometryReader { proxy in
            let placement = GridPlacement(
                crossCount: columns.count,
                packing: packing,
                crossSpans: items.map { $0.containerValues.gridSpan.column },
                mainSpans: items.map { $0.containerValues.gridSpan.row }
            )
            let columnTracks = resolveGridTracks(columns, totalLength: proxy.size.width, spacing: spacing)
            let rowTracks = resolveGridTracks(rows, totalLength: proxy.size.height, spacing: spacing)

            ZStack(alignment: .topLeading) {
                ForEach(indexedItems) { entry in
                    let cell = placement.cell(for: entry.index)
                    let columnRange = spannedTrackRange(columnTracks, start: cell.cross, span: cell.crossSpan)
                    let rowRange = spannedTrackRange(rowTracks, start: cell.main, span: cell.mainSpan)

                    entry.item
                        .frame(width: columnRange.length, height: rowRange.length)
                        .offset(x: columnRange.origin, y: rowRange.origin)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private var indexedItems: [IndexedSubview] {
        items.enumerated().map { IndexedSubview(index: $0.offset, item: $0.element) }
    }
}

private struct IndexedSubview: Identifiable {
    var index: Int
    var item: Subview

    var id: Subview.ID { item.id }
}
