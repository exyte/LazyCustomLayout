@testable import LazyCustomLayout

/// A fully-known, in-memory sequence of ids, with an optional subset marked
/// as "loaded" to simulate a window that hasn't streamed in neighbors yet.
/// Ids outside `ids` entirely don't exist — asking about their neighbors is a
/// test setup error, not a real `.unloaded`/`.dataEnd` case.
@MainActor
final class FakeAnchorDataSource: AnchorResolverDataSource {
    typealias ID = Int

    var ids: [Int]
    var loadedIDs: Set<Int>

    init(ids: [Int], loadedIDs: Set<Int>? = nil) {
        self.ids = ids
        self.loadedIDs = loadedIDs ?? Set(ids)
    }

    func boundary(after id: Int) -> AnchorBoundary<Int> {
        guard let index = ids.firstIndex(of: id) else { return .dataEnd }

        let nextIndex = index + 1
        guard nextIndex < ids.count else { return .dataEnd }

        let nextID = ids[nextIndex]
        return loadedIDs.contains(nextID) ? .item(nextID) : .unloaded
    }

    func boundary(before id: Int) -> AnchorBoundary<Int> {
        guard let index = ids.firstIndex(of: id) else { return .dataEnd }

        let previousIndex = index - 1
        guard previousIndex >= 0 else { return .dataEnd }

        let previousID = ids[previousIndex]
        return loadedIDs.contains(previousID) ? .item(previousID) : .unloaded
    }
}
