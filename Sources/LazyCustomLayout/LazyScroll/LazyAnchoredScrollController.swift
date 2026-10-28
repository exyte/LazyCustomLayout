import Observation
import QuartzCore
import SwiftUI

/// Drives `LazyAnchoredScroll`: wires the drag/fling `ScrollEngine` to a
/// `StreamingAnchorPositionState` instead of a flat offset, and answers the
/// engine's slack queries through it too, so a real delta and a slack query
/// always agree on where the true edge is.
@MainActor
@Observable
final class LazyAnchoredScrollController<Layout: StreamingLayout>: ScrollEngineDelegate {
    var axis: ScrollAxis
    var viewportSize: CGSize = .zero {
        didSet { streamingAnchor.viewportSize = viewportSize }
    }

    /// Mirrors `LazyAnchoredScroll`'s own `\.lazyLayoutSizing` environment
    /// read — kept here too so `dragChanged`/`dragEnded`/`touchDown` can
    /// gate on it without the view needing to conditionally attach/detach
    /// its gesture modifiers.
    var sizing: LazyLayoutSizing = .scrollFillingSpace

    /// The full content length along `axis`, known for certain only once a
    /// window walk has reached both true edges (`forwardSlack` and
    /// `backwardSlack` both resolve) — `nil` otherwise, meaning `.scroll`
    /// sizing falls back to an estimate. See `currentWindow(itemCount:viewportSize:)`.
    private(set) var knownContentLength: Double?

    /// Whether this container's content is longer than its own viewport —
    /// `true` (the conservative default) until `knownContentLength` resolves
    /// for certain, since a window that hasn't reached both edges yet might
    /// still turn out to overflow once it does.
    var contentOverflows: Bool {
        guard let knownContentLength else { return true }

        let viewportLength = axis == .vertical ? viewportSize.height : viewportSize.width
        return knownContentLength > viewportLength
    }

    let sizeCache: SizeCache<Int>
    /// Measured cross-axis length per item — only consulted by a layout
    /// that proposes a nil cross length to let an item size itself (a
    /// variable-width flow tag, a grid's auto-measured column); every other
    /// layout proposes a fixed cross length and this stays unused.
    let crossSizeCache: SizeCache<Int>

    /// Visual-only rubber-band stretch past a true edge, kept separate from
    /// `anchor` — `StreamingAnchorPositionState` structurally clamps at the
    /// true start/end and reports whatever it can't resolve as `.dataEnd`
    /// rather than discarding it, so routing the engine's overscroll deltas
    /// through it directly would silently swallow the stretch while the
    /// engine still thinks it owes a spring bounce-back, which then lands as
    /// a real forward/backward anchor move instead of undoing a stretch
    /// that (as far as the anchor's concerned) never happened. Mirrors
    /// `ScrollEngine`'s own honest-vs-overscroll split, one layer up.
    private(set) var overscrollOffset: Double = 0

    private let streamingAnchor: StreamingAnchorPositionState<Layout>
    private let engine: ScrollEngine
    private let clock = FrameClock()
    private var lastTranslation: Double = 0

    init(
        axis: ScrollAxis,
        itemCount: Int,
        layout: Layout,
        estimatedItemLength: Double,
        bufferLength: Double?,
        maxLoadedItems: Int?
    ) {
        self.axis = axis

        let sizeCache = SizeCache<Int>()
        let crossSizeCache = SizeCache<Int>()
        self.sizeCache = sizeCache
        self.crossSizeCache = crossSizeCache
        self.streamingAnchor = StreamingAnchorPositionState(
            axis: axis,
            itemCount: itemCount,
            layout: layout,
            sizeCache: sizeCache,
            crossSizeCache: crossSizeCache,
            estimatedItemLength: estimatedItemLength,
            bufferLength: bufferLength,
            maxLoadedItems: maxLoadedItems
        )

        self.engine = ScrollEngine(clock: clock)
        self.engine.delegate = self
        self.engine.onDelta = { [weak self] delta in
            self?.applyEngineDelta(delta)
        }
    }

    var anchor: ScrollAnchor<Int> { streamingAnchor.anchor }

    /// See `StreamingAnchorPositionState.window(itemCount:viewportSize:)` —
    /// `LazyAnchoredScroll.body`'s own entry point into the same cached walk
    /// `slack`/`applyDelta` use internally.
    func currentWindow(itemCount: Int, viewportSize: CGSize) -> StreamingLayoutWindow {
        let window = streamingAnchor.window(itemCount: itemCount, viewportSize: viewportSize)
        updateKnownContentLength(window: window)
        return window
    }

    /// Only resolvable once the window has walked all the way to both true
    /// edges — `forwardSlack`/`backwardSlack` only come back non-`nil` when
    /// the walk actually reached that edge (see `streamingLayoutWindow`), so
    /// their presence here is exactly the signal "nothing beyond what's
    /// loaded right now."
    private func updateKnownContentLength(window: StreamingLayoutWindow) {
        guard window.forwardSlack != nil, window.backwardSlack != nil else { return }

        let frames = window.indices.compactMap { window.frames[$0] }
        guard !frames.isEmpty else { return }

        func origin(_ frame: CGRect) -> Double { axis == .vertical ? frame.minY : frame.minX }
        func end(_ frame: CGRect) -> Double { axis == .vertical ? frame.maxY : frame.maxX }

        let length = (frames.map(end).max() ?? 0) - (frames.map(origin).min() ?? 0)

        if knownContentLength != length {
            knownContentLength = length
        }
    }

    private func applyEngineDelta(_ delta: Double) {
        guard overscrollOffset != 0 else {
            let leftover = streamingAnchor.applyDelta(delta)

            switch leftover {
            case .none:
                break
            case .dataEnd(let remaining):
                overscrollOffset += remaining
            case .unloaded:
                // An item whose size isn't measured yet is unknown, not
                // the true edge — stretching here would leave
                // `overscrollOffset` stuck non-zero (the engine never
                // owes a bounce-back for it), shifting content off screen.
                break
            }

            return
        }

        let wouldCrossZero = (overscrollOffset > 0 && overscrollOffset + delta < 0)
            || (overscrollOffset < 0 && overscrollOffset + delta > 0)

        guard wouldCrossZero else {
            overscrollOffset += delta
            return
        }

        let toZero = -overscrollOffset
        overscrollOffset = 0
        applyEngineDelta(delta - toZero)
    }

    func dragChanged(_ value: ScrollDragGesture.Value) {
        guard allowsDragHandling else { return }

        let translation = axis == .vertical ? value.translation.height : value.translation.width
        let delta = translation - lastTranslation
        lastTranslation = translation

        engine.dragChanged(delta: -delta, time: CACurrentMediaTime())
    }

    func dragEnded(_ value: ScrollDragGesture.Value) {
        guard allowsDragHandling else { return }

        lastTranslation = 0
        let velocity = axis == .vertical ? value.velocity.height : value.velocity.width
        engine.dragEnded(fallbackVelocity: -velocity)
    }

    func touchDown() {
        guard allowsDragHandling else { return }

        engine.touchDown()
    }

    /// `.scrollFillingSpace` always drags; `.scroll` only once content
    /// actually overflows (`.fitToContent` never reaches this at all — its
    /// `EagerStreamingLayout` content never attaches a gesture in the first
    /// place). Otherwise this container's own pan recognizer would still
    /// recognize every drag that starts over it
    /// (`ScrollDragGesture.Coordinator.shouldRecognizeSimultaneouslyWith`
    /// always returns `true`, so a parent scroll view it's nested inside
    /// keeps scrolling regardless), converting the whole thing straight
    /// into visible rubber-band overscroll with nothing to actually scroll.
    private var allowsDragHandling: Bool {
        sizing == .scrollFillingSpace || contentOverflows
    }

    // MARK: ScrollEngineDelegate

    func scrollEngineViewportLength(_ engine: ScrollEngine) -> Double {
        axis == .vertical ? viewportSize.height : viewportSize.width
    }

    func scrollEngine(_ engine: ScrollEngine, slackInDirection direction: ScrollEngine.Direction) -> Double? {
        streamingAnchor.slack(direction: direction)
    }
}
