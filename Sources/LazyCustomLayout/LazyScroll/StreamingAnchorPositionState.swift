import Observation
import SwiftUI

/// Resolves item ordering against a fixed `count`, with no notion of a
/// loaded/unloaded window — `LazyAnchoredScroll`'s `data` is a plain
/// `RandomAccessCollection` known in full up front, unlike a paged/streaming
/// data source. Revisit once loading more data in needs `onReachStart`/
/// `onReachEnd` to actually page something in.
struct ArrayIndexDataSource: AnchorResolverDataSource {
    typealias ID = Int

    var count: Int

    func boundary(after id: Int) -> AnchorBoundary<Int> {
        id + 1 < count ? .item(id + 1) : .dataEnd
    }

    func boundary(before id: Int) -> AnchorBoundary<Int> {
        id - 1 >= 0 ? .item(id - 1) : .dataEnd
    }
}

/// Drives a `LazyAnchoredScroll`'s anchor for a particular `layout`,
/// resolving deltas against that layout's real geometry instead of
/// `AnchorResolver`'s generic per-item-length walk — correct only for a
/// single sequential column, not for a layout whose items don't run along
/// one line (masonry's lanes, flow's lines, where the next index can sit
/// anywhere relative to the current one, even behind it).
///
/// Wraps a plain `ScrollPositionState<ArrayIndexDataSource>` for the parts
/// that generic walk already gets right — data-end detection,
/// `onReachStart`/`onReachEnd`, `scrollTo`/`animateScrollTo` — and corrects
/// only the (id, offset) that walk lands on, by re-`scrollTo`-ing to wherever
/// this same `StreamingLayoutWindow` (the one the container already computes
/// to render and to answer the scroll engine's slack queries) shows the
/// delta truly landing. That correction is this type's entire reason to
/// exist, so it happens as a normal, private part of `applyDelta` here — not
/// something a caller has to remember to apply afterward. An earlier
/// revision instead had the controller call a bespoke `correctAnchor` on
/// `ScrollPositionState` from outside, right after its own `applyDelta`; that
/// both split the geometry-aware half of "apply a delta" into a different
/// type than the half that decides whether a boundary was crossed, and
/// duplicated what `scrollTo` already did.
///
/// `animateScrollTo`'s own distance resolution still inherits the inner
/// `ScrollPositionState`'s sequential-walk assumption — unexercised by any
/// example yet, but the same root issue `applyDelta` had before this type
/// existed, just not yet hit in practice.
@MainActor
@Observable
final class StreamingAnchorPositionState<Layout: StreamingLayout> {
    var onReachStart: (() -> Void)? {
        get { inner.onReachStart }
        set { inner.onReachStart = newValue }
    }

    var onReachEnd: (() -> Void)? {
        get { inner.onReachEnd }
        set { inner.onReachEnd = newValue }
    }

    var viewportSize: CGSize = .zero

    private let inner: ScrollPositionState<ArrayIndexDataSource>
    private let sizeCache: SizeCache<Int>
    private let crossSizeCache: SizeCache<Int>
    private let layout: Layout
    private let axis: ScrollAxis
    private let itemCount: Int
    private let estimatedItemLength: Double
    private let bufferLength: Double?
    private let maxLoadedItems: Int?

    private var cachedWindowKey: WindowCacheKey?
    private var cachedWindow: StreamingLayoutWindow?

    init(
        axis: ScrollAxis,
        itemCount: Int,
        layout: Layout,
        sizeCache: SizeCache<Int>,
        crossSizeCache: SizeCache<Int>,
        estimatedItemLength: Double,
        bufferLength: Double?,
        maxLoadedItems: Int?
    ) {
        self.axis = axis
        self.itemCount = itemCount
        self.layout = layout
        self.sizeCache = sizeCache
        self.crossSizeCache = crossSizeCache
        self.estimatedItemLength = estimatedItemLength
        self.bufferLength = bufferLength
        self.maxLoadedItems = maxLoadedItems
        self.inner = ScrollPositionState(
            anchor: ScrollAnchor(id: 0),
            dataSource: ArrayIndexDataSource(count: itemCount),
            sizeCache: sizeCache
        )
    }

    var anchor: ScrollAnchor<Int> { inner.anchor }

    func scrollTo(id: Int, offset: Double = 0) {
        inner.scrollTo(id: id, offset: offset)
    }

    func animateScrollTo(id: Int, maxResolvableSteps: Int = 30) {
        inner.animateScrollTo(id: id, maxResolvableSteps: maxResolvableSteps)
    }

    /// Resolves `direction`'s rubber-band slack from this same window-based
    /// geometry `applyDelta` uses, so a real delta and a slack query always
    /// agree on where the true edge is.
    func slack(direction: ScrollEngine.Direction) -> Double? {
        let window = windowAroundAnchor()

        switch direction {
        case .forward: return window.forwardSlack
        case .backward: return window.backwardSlack
        }
    }

    @discardableResult
    func applyDelta(_ delta: Double) -> AnchorResolver<ArrayIndexDataSource>.Leftover {
        // `AnchorResolver` walks ids using each item's own measured length as
        // both the distance to the next one *and* the signal for having run
        // off the true data end — both assume items run along a single line.
        // For a multi-lane/multi-item-per-line layout this can understate the
        // true edge distance enough that the resolver never notices it ran
        // past the real start/end at all (a large reversal fling computing
        // as "still fits, lands at item 0" when the true geometry had
        // already run off the start partway through that delta), silently
        // swallowing what should have been rubber-band overscroll. This
        // window's own forward/backward slack is computed from the real
        // layout geometry (`StreamingLayoutWalker`), so clamp the delta to
        // it first and report any excess as `.dataEnd`, before the resolver
        // ever sees it.
        let previousAnchor = anchor
        let window = windowAroundAnchor()

        let boundedDelta: Double
        let overshoot: Double
        if delta > 0, let forwardSlack = window.forwardSlack, delta > forwardSlack {
            (boundedDelta, overshoot) = (forwardSlack, delta - forwardSlack)
        } else if delta < 0, let backwardSlack = window.backwardSlack, -delta > backwardSlack {
            (boundedDelta, overshoot) = (-backwardSlack, delta + backwardSlack)
        } else {
            (boundedDelta, overshoot) = (delta, 0)
        }

        let targetLocalPosition = previousAnchor.offset + boundedDelta
        let leftover = inner.applyDelta(boundedDelta)

        // Id and offset must be corrected together: patching only the offset
        // while keeping whatever id the resolver guessed can leave it
        // outside that id's own [0, length) range, which corrupts the very
        // invariant the resolver's *next* call silently assumes.
        if anchor.id != previousAnchor.id, let corrected = trueAnchor(atLocalPosition: targetLocalPosition, in: window) {
            inner.scrollTo(id: corrected.id, offset: corrected.offset)
        }

        guard overshoot != 0 else { return leftover }

        if case .dataEnd = leftover {
            // Already fired by `inner.applyDelta` itself for the bounded
            // delta; avoid firing onReachStart/onReachEnd twice.
        } else {
            overshoot < 0 ? inner.onReachStart?() : inner.onReachEnd?()
        }

        return .dataEnd(overshoot)
    }

    // MARK: Window-based resolution

    private func windowAroundAnchor() -> StreamingLayoutWindow {
        window(itemCount: itemCount, viewportSize: viewportSize)
    }

    /// Shared by `slack`, `applyDelta`, and `LazyAnchoredScroll.body` — all
    /// three used to each walk the layout fresh on every call, even though
    /// most of the time nothing about the anchor or what's measured had
    /// changed since the last one (3 walks per frame during a fling, each
    /// as expensive as the last). Cached by every input the walk actually
    /// depends on, so repeating the same query is O(1). `itemCount` and
    /// `viewportSize` come in as parameters rather than reading `self`'s own
    /// copies because `LazyAnchoredScroll.body` tracks `data.count` and
    /// `GeometryReader`'s `proxy.size` live, while this type's own copies
    /// are only as fresh as its last `viewportSize` write.
    func window(itemCount: Int, viewportSize: CGSize) -> StreamingLayoutWindow {
        let key = WindowCacheKey(
            anchorID: anchor.id,
            anchorOffset: anchor.offset,
            itemCount: itemCount,
            viewportSize: viewportSize,
            sizeCacheVersion: sizeCache.version,
            crossSizeCacheVersion: crossSizeCache.version
        )

        if let cachedWindow, cachedWindowKey == key {
            return cachedWindow
        }

        let window = streamingLayoutWindow(
            anchor: anchor,
            itemCount: itemCount,
            axis: axis,
            viewportSize: viewportSize,
            bufferLength: bufferLength ?? (axis == .vertical ? viewportSize.height : viewportSize.width),
            maxLoadedItems: maxLoadedItems,
            estimatedItemLength: estimatedItemLength,
            sizeCache: sizeCache,
            crossSizeCache: crossSizeCache,
            layout: layout
        )

        cachedWindowKey = key
        cachedWindow = window
        return window
    }

    private struct WindowCacheKey: Equatable {
        var anchorID: Int
        var anchorOffset: Double
        var itemCount: Int
        var viewportSize: CGSize
        var sizeCacheVersion: Int
        var crossSizeCacheVersion: Int
    }

    /// Which item `window` (walked relative to some previous anchor) truly
    /// contains `targetLocalPosition`, and the offset into it — the item with
    /// the largest origin at or before that position, so the resulting
    /// offset is always `>= 0` by construction. Returns `nil` only if
    /// `targetLocalPosition` falls outside everything `window` loaded (e.g. a
    /// single delta large enough to jump past its own reach), in which case
    /// the caller keeps `AnchorResolver`'s own (less precise, but always
    /// in-range) answer.
    private func trueAnchor(atLocalPosition targetLocalPosition: Double, in window: StreamingLayoutWindow) -> (id: Int, offset: Double)? {
        var best: (id: Int, origin: Double)?

        for (index, frame) in window.frames {
            let origin = axis == .vertical ? frame.minY : frame.minX
            guard origin <= targetLocalPosition, best.map({ origin > $0.origin }) ?? true else { continue }
            best = (id: index, origin: origin)
        }

        return best.map { (id: $0.id, offset: targetLocalPosition - $0.origin) }
    }
}
