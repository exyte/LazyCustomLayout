import Observation

/// Measured sizes along the scroll axis, keyed by item id. Kept around after
/// an item unloads so it comes back at the same size instead of needing to
/// be re-measured, and lets `AnchorResolver` walk across already-seen
/// boundaries without the item needing to be loaded right now.
///
/// `@Observable` so a SwiftUI layout pass that reads a size through the
/// subscript — directly, or via `streamingLayoutWindow` — re-runs once that
/// size (or any other) is actually measured.
@MainActor
@Observable
public final class SizeCache<ID: Hashable> {
    private var sizesByID: [ID: Double] = [:]
    private var sum: Double = 0

    /// Bumped only when a stored value actually changes. `measuringSize`
    /// reports a size on every `onAppear`/`onChange`, including ones where
    /// the value hasn't moved — without the dedupe below, that wrote (and
    /// `@Observable`-invalidated) the cache on every one of those too,
    /// triggering an extra layout pass each time. Also lets a window-walk
    /// cache (`StreamingAnchorPositionState.window(itemCount:viewportSize:)`)
    /// tell "nothing measured changed" apart from "something did" without
    /// diffing the whole dictionary.
    private(set) var version = 0

    public init() {}

    public subscript(id: ID) -> Double? {
        get { sizesByID[id] }
        set {
            guard sizesByID[id] != newValue else { return }

            if let oldValue = sizesByID[id] {
                sum -= oldValue
            }
            if let newValue {
                sum += newValue
            }
            sizesByID[id] = newValue
            version += 1
        }
    }

    /// The mean of every measured size so far. `nil` until at least one size
    /// is known. Used to estimate distances into unmeasured content, e.g.
    /// for an approximate scroll indicator.
    ///
    /// Kept as an O(1) running sum/count rather than reducing over
    /// `sizesByID` on every read — this is queried for every unmeasured item
    /// `StreamingLayoutWalker` places, which happens on every gesture and
    /// fling tick, so an O(n) scan here would scale with how much content
    /// has been measured and stall scrolling on large lists.
    public var averageSize: Double? {
        guard !sizesByID.isEmpty else { return nil }

        return sum / Double(sizesByID.count)
    }
}
