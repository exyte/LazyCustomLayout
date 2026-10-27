import SwiftUI

/// A manually-driven scroll container: `ScrollEngine`'s physics and gestures
/// applied to a single piece of content, no `UIScrollView` underneath. Needs
/// nothing but its content — the same way `ScrollView` itself needs nothing
/// but its content — with `axis` the only thing to configure.
///
/// For one eagerly-rendered piece of content, not a collection — there's no
/// item data and nothing is windowed in/out as it scrolls. Reach for
/// `LazyAnchoredScroll` instead once there's a `RandomAccessCollection` to
/// render lazily through a `StreamingLayout`.
public struct AnchoredScrollView<Content: View>: View {
    var axis: ScrollAxis
    var content: () -> Content

    @State private var controller: SingleContentScrollController

    public init(axis: ScrollAxis = .vertical, @ViewBuilder content: @escaping () -> Content) {
        self.axis = axis
        self.content = content
        _controller = State(initialValue: SingleContentScrollController(axis: axis))
    }

    public var body: some View {
        GeometryReader { proxy in
            let viewportLength = axis == .vertical ? proxy.size.height : proxy.size.width

            content()
                .frame(
                    maxWidth: axis == .vertical ? .infinity : nil,
                    maxHeight: axis == .horizontal ? .infinity : nil,
                    alignment: axis == .vertical ? .leading : .center
                )
                .fixedSize(horizontal: axis == .horizontal, vertical: axis == .vertical)
                .measuringLength(axis: axis) { controller.contentLength = $0 }
                .offset(
                    x: axis == .horizontal ? -controller.offset : 0,
                    y: axis == .vertical ? -controller.offset : 0
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: axis == .vertical ? .top : .leading)
                .clipped()
                .contentShape(Rectangle())
                .onAppear { controller.viewportLength = viewportLength }
                .onChange(of: viewportLength) { _, newValue in controller.viewportLength = newValue }
                .gesture(ScrollDragGesture(
                    onChanged: { controller.dragChanged($0) },
                    onEnded: { controller.dragEnded($0) }
                ))
                .gesture(ScrollTouchDownGesture(onTouchDown: { controller.touchDown() }))
        }
    }
}
