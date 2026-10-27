import SwiftUI
import Testing
@testable import LazyCustomLayout

@MainActor
@Suite("FlowLayout line breaks")
struct FlowLineBreakTests {

    /// 5 items, each 100pt wide, in a 300pt-wide viewport with no spacing —
    /// exactly 3 fit per line, so item 3 should wrap.
    func makeWindow(anchor: ScrollAnchor<Int> = ScrollAnchor(id: 0)) -> StreamingLayoutWindow {
        let sizeCache = SizeCache<Int>()
        let crossSizeCache = SizeCache<Int>()
        for index in 0..<5 {
            sizeCache[index] = 50
            crossSizeCache[index] = 100
        }

        return streamingLayoutWindow(
            anchor: anchor,
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
    }

    @Test("items that fit the current line's width stay on it; the first that doesn't wraps")
    func wrapsOnceLineIsFull() {
        let window = makeWindow()

        #expect(window.frames[0]?.minY == 0)
        #expect(window.frames[1]?.minY == 0)
        #expect(window.frames[2]?.minY == 0)
        #expect(window.frames[3]?.minY == 60) // 50 (line 0's height) + 10 lineSpacing
        #expect(window.frames[4]?.minY == 60)
    }

    @Test("items on the same line sit side by side with no gaps")
    func sameLineItemsSitSideBySide() {
        let window = makeWindow()

        #expect(window.frames[0]?.minX == 0)
        #expect(window.frames[1]?.minX == 100)
        #expect(window.frames[2]?.minX == 200)
        #expect(window.frames[3]?.minX == 0) // new line resets the cross origin
        #expect(window.frames[4]?.minX == 100)
    }

    @Test("whichever item is anchor sits at local origin 0, regardless of which line it's on")
    func anchorAlwaysSitsAtLocalOriginZero() {
        let window = makeWindow(anchor: ScrollAnchor(id: 3))

        #expect(window.frames[3]?.minY == 0)
        // Item 0 is a full line *above* the anchor's line, so it sits at a
        // negative local offset once the anchor is translated to origin 0.
        #expect(window.frames[0]?.minY == -60)
    }
}
