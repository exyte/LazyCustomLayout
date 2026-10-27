import SwiftUI

extension View {
    /// Reports this view's length along `axis` whenever it changes, via a
    /// zero-cost background `GeometryReader` — the measuring technique any
    /// content needs to report its own size to a manually scrolled container.
    public func measuringLength(axis: ScrollAxis, _ onChange: @escaping (Double) -> Void) -> some View {
        measuringSize { onChange(axis == .vertical ? $0.height : $0.width) }
    }

    /// Reports this view's full size whenever it changes, via a zero-cost
    /// background `GeometryReader` — used where both dimensions matter, e.g.
    /// feeding a `StreamingLayout`'s `place(size:context:cache:)`.
    public func measuringSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.size) }
                    .onChange(of: proxy.size) { _, newValue in onChange(newValue) }
            }
        }
    }
}
