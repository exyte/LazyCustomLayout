import SwiftUI

/// `LazyAnchoredScroll` + `FlowLayout`, one line: variable-width items
/// wrapping left-to-right (or top-to-bottom on a horizontal axis), like a
/// tag cloud.
public struct LazyFlow<Data: RandomAccessCollection, Content: View>: View where Data.Index == Int {
    var data: Data
    var axis: ScrollAxis
    var spacing: Double
    var lineSpacing: Double
    var estimatedItemLength: Double
    var bufferLength: Double?
    var maxLoadedItems: Int?
    var id: (Int, Data.Element) -> AnyHashable
    var content: (Data.Element) -> Content

    public init(
        _ data: Data,
        axis: ScrollAxis = .vertical,
        spacing: Double = 8,
        lineSpacing: Double = 8,
        estimatedItemLength: Double,
        bufferLength: Double? = nil,
        maxLoadedItems: Int? = nil,
        id: @escaping (Int, Data.Element) -> AnyHashable = { index, _ in AnyHashable(index) },
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.axis = axis
        self.spacing = spacing
        self.lineSpacing = lineSpacing
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
            layout: FlowLayout(spacing: spacing, lineSpacing: lineSpacing),
            estimatedItemLength: estimatedItemLength,
            bufferLength: bufferLength,
            maxLoadedItems: maxLoadedItems,
            id: id,
            content: content
        )
    }
}
