import SwiftUI

/// Assigns a stable "slot" number to each currently-visible item id,
/// reusing whichever slot a now-offscreen id vacated for the next id
/// that enters the window — the same cell-recycling idea `UITableView` uses,
/// applied to SwiftUI identity instead of `UIView` instances.
///
/// `LazyAnchoredScroll` used to key its `ForEach` by each item's own
/// identity, so every item crossing the buffer boundary during a scroll
/// was a SwiftUI insert or remove — for a cell with many subviews, that's
/// many AttributeGraph nodes built or torn down per item, every time.
/// Keying by slot instead means crossing the boundary is a content *update*
/// to an already-mounted identity, not an insert/remove.
///
/// Keyed by id rather than by the window's raw index: when the same id
/// reappears at a different index within one window (e.g. a `gridSpan`
/// change repacking `LazyGrid`), it keeps its slot, so only that slot's
/// frame/offset changes instead of two unrelated slots being freed and
/// claimed — letting SwiftUI animate the move instead of cross-dissolving.
/// A caller that doesn't care about that distinction can just pass the
/// default index-based `id:`, which degrades to the old index-keyed
/// behavior.
///
/// `indexForSlot` only ever grows, never shrinks: a slot that falls idle
/// (its id scrolled out and nothing new has taken it yet) keeps its
/// last-known index rather than being removed, so the identity set
/// `ForEach` sees stays stable across the whole scroll session instead of
/// churning every time the window's size happens to change.
@MainActor
final class ReusePool {
    private(set) var indexForSlot: [Int] = []
    private var activeSlotForID: [AnyHashable: Int] = [:]
    private var activeSlots: Set<Int> = []
    private var freeSlots: [Int] = []

    var slots: Range<Int> { indexForSlot.indices }

    func assign(items: [(index: Int, id: AnyHashable)]) {
        let visible = Set(items.map(\.id))

        for (id, slot) in activeSlotForID where !visible.contains(id) {
            freeSlots.append(slot)
        }
        activeSlotForID = activeSlotForID.filter { visible.contains($0.key) }

        for item in items {
            if let slot = activeSlotForID[item.id] {
                indexForSlot[slot] = item.index
            } else {
                let slot: Int
                if let freeSlot = freeSlots.popLast() {
                    slot = freeSlot
                    indexForSlot[slot] = item.index
                } else {
                    slot = indexForSlot.count
                    indexForSlot.append(item.index)
                }
                activeSlotForID[item.id] = slot
            }
        }

        activeSlots = Set(activeSlotForID.values)
    }

    func index(forSlot slot: Int) -> Int {
        indexForSlot[slot]
    }

    func isActive(slot: Int) -> Bool {
        activeSlots.contains(slot)
    }
}

extension EnvironmentValues {
    /// Whether `LazyAnchoredScroll` reuses a stable pool of cell identities
    /// instead of one identity per item. Set via `View.cellReuse(_:)`.
    @Entry var cellReuseEnabled = true
}
