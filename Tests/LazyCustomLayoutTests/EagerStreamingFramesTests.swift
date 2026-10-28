import SwiftUI
import Testing
@testable import LazyCustomLayout

@MainActor
@Suite("eagerStreamingFrames")
struct EagerStreamingFramesTests {

    /// Same fixed item sizes and the same `FlowLayout` config as
    /// `FlowLineBreakTests.makeWindow` — 5 items, 100pt wide, in a 300pt-wide
    /// viewport with no spacing, so exactly 3 fit per line.
    private func makeFrames() -> [CGRect] {
        eagerStreamingFrames(
            axis: .vertical,
            itemCount: 5,
            viewportSize: CGSize(width: 300, height: Double.infinity),
            layout: FlowLayout(spacing: 0, lineSpacing: 10)
        ) { _, _ in CGSize(width: 100, height: 50) }
    }

    @Test("eager placement wraps the same way the lazy windowed walk does")
    func matchesLazyWindow() {
        let sizeCache = SizeCache<Int>()
        let crossSizeCache = SizeCache<Int>()
        for index in 0..<5 {
            sizeCache[index] = 50
            crossSizeCache[index] = 100
        }

        let window = streamingLayoutWindow(
            anchor: ScrollAnchor(id: 0),
            itemCount: 5,
            axis: .vertical,
            viewportSize: CGSize(width: 300, height: 1000),
            bufferLength: 1000,
            maxLoadedItems: nil,
            estimatedItemLength: 50,
            sizeCache: sizeCache,
            crossSizeCache: crossSizeCache,
            layout: FlowLayout(spacing: 0, lineSpacing: 10)
        )

        let frames = makeFrames()

        for index in 0..<5 {
            #expect(frames[index] == window.frames[index])
        }
    }

    @Test("every item is placed, none stopped short by a window reach")
    func placesEveryItemRegardlessOfReach() {
        #expect(makeFrames().count == 5)
    }
}
