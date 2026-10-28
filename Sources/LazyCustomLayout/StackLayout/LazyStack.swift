import SwiftUI

/// `LazyAnchoredScroll` + `StackLayout`, one line: items placed one after
/// another along the scroll axis, each sized to itself — a lazy table/list.
///
/// Sizes itself along the scroll axis per `.lazyLayoutSizing(_:)` — hugs
/// content up to the offered space and scrolls beyond it by default.
public struct LazyStack<Data: RandomAccessCollection, Content: View>: View where Data.Index == Int {
    var data: Data
    var axis: ScrollAxis
    var spacing: Double
    var estimatedItemLength: Double
    var bufferLength: Double?
    var maxLoadedItems: Int?
    var id: (Int, Data.Element) -> AnyHashable
    var content: (Data.Element) -> Content

    public init(
        _ data: Data,
        axis: ScrollAxis = .vertical,
        spacing: Double = 0,
        estimatedItemLength: Double,
        bufferLength: Double? = nil,
        maxLoadedItems: Int? = nil,
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.axis = axis
        self.spacing = spacing
        self.estimatedItemLength = estimatedItemLength
        self.bufferLength = bufferLength
        self.maxLoadedItems = maxLoadedItems
        self.id = id
        self.content = content
    }

    public var body: some View {
        LazyAnchoredScroll(
            data,
            axis: axis,
            layout: StackLayout(spacing: spacing),
            estimatedItemLength: estimatedItemLength,
            bufferLength: bufferLength,
            maxLoadedItems: maxLoadedItems,
            id: id,
            content: content
        )
    }
}
