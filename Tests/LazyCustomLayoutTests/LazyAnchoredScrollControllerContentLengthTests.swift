import SwiftUI
import Testing
@testable import LazyCustomLayout

@MainActor
@Suite("LazyAnchoredScrollController content length")
struct LazyAnchoredScrollControllerContentLengthTests {

    @Test("knownContentLength stays nil until the window reaches both true edges")
    func staysNilUntilFullySpanned() {
        let controller = LazyAnchoredScrollController(
            axis: .vertical,
            itemCount: 5,
            layout: StackLayout(spacing: 10),
            estimatedItemLength: 50,
            bufferLength: nil,
            maxLoadedItems: nil
        )

        // A viewport (and default buffer, which mirrors it) too small to
        // reach the last item — the forward walk breaks on `reach`, not on
        // hitting `itemCount - 1`, so `forwardSlack` never resolves.
        _ = controller.currentWindow(itemCount: 5, viewportSize: CGSize(width: 300, height: 10))

        #expect(controller.knownContentLength == nil)
    }

    @Test("knownContentLength resolves to the real total once both edges are reached")
    func resolvesOnceFullySpanned() {
        let controller = LazyAnchoredScrollController(
            axis: .vertical,
            itemCount: 5,
            layout: StackLayout(spacing: 10),
            estimatedItemLength: 50,
            bufferLength: nil,
            maxLoadedItems: nil
        )

        // Generous enough to walk from the anchor all the way to both true
        // edges in a single pass.
        _ = controller.currentWindow(itemCount: 5, viewportSize: CGSize(width: 300, height: 1000))

        // 5 items @ 50pt (the estimate, nothing's been measured) + 4 gaps @ 10pt spacing.
        #expect(controller.knownContentLength == Double(5 * 50 + 4 * 10))
    }

    @Test("contentOverflows is true by default and false once content is known to fit")
    func contentOverflowsReflectsKnownLength() {
        let controller = LazyAnchoredScrollController(
            axis: .vertical,
            itemCount: 5,
            layout: StackLayout(spacing: 10),
            estimatedItemLength: 50,
            bufferLength: nil,
            maxLoadedItems: nil
        )

        #expect(controller.contentOverflows)

        controller.viewportSize = CGSize(width: 300, height: 1000)
        _ = controller.currentWindow(itemCount: 5, viewportSize: controller.viewportSize)

        #expect(!controller.contentOverflows)
    }
}
