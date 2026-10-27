/// What lies in a given direction from an item, as far as the data source
/// currently knows.
public enum AnchorBoundary<ID: Hashable>: Equatable {
    /// Another item, already loaded.
    case item(ID)
    /// Nothing loaded yet in that direction — not necessarily the end of the
    /// data, just unknown. `AnchorResolver` treats this as unbounded.
    case unloaded
    /// The true start/end of the data, not just the loaded window.
    case dataEnd
}

/// Supplies the ordering `AnchorResolver` needs to walk a delta across item
/// boundaries, without it needing to know how the data is stored or how much
/// of it is currently loaded.
@MainActor
public protocol AnchorResolverDataSource<ID> {
    associatedtype ID: Hashable

    func boundary(after id: ID) -> AnchorBoundary<ID>
    func boundary(before id: ID) -> AnchorBoundary<ID>
}

/// Walks a delta across item boundaries using sizes from a `SizeCache`,
/// keeping `anchor` as (item id, offset within it) rather than an absolute
/// position — so inserting items above the anchor never moves it.
@MainActor
public final class AnchorResolver<DataSource: AnchorResolverDataSource> {
    public typealias ID = DataSource.ID

    /// Delta that couldn't be resolved, in the same sign convention as the
    /// delta passed to `applyDelta` (positive = forward). `.dataEnd` means it
    /// ran off the true start/end of the data — hand this to rubber-banding.
    /// `.unloaded` means it ran into an item whose size isn't known yet —
    /// treat as unbounded, don't rubber-band.
    public enum Leftover: Equatable {
        case none
        case dataEnd(Double)
        case unloaded(Double)
    }

    public private(set) var anchor: ScrollAnchor<ID>

    public var dataSource: DataSource
    public var sizeCache: SizeCache<ID>

    public init(anchor: ScrollAnchor<ID>, dataSource: DataSource, sizeCache: SizeCache<ID>) {
        self.anchor = anchor
        self.dataSource = dataSource
        self.sizeCache = sizeCache
    }

    public func setAnchor(_ anchor: ScrollAnchor<ID>) {
        self.anchor = anchor
    }

    @discardableResult
    public func applyDelta(_ delta: Double) -> Leftover {
        guard delta != 0 else { return .none }

        guard delta > 0 else {
            switch applyBackward(-delta) {
            case .none: return .none
            case .dataEnd(let remaining): return .dataEnd(-remaining)
            case .unloaded(let remaining): return .unloaded(-remaining)
            }
        }

        return applyForward(delta)
    }

    // MARK: Walking

    private func applyForward(_ amount: Double) -> Leftover {
        var remaining = amount

        while remaining > 0 {
            guard let size = sizeCache[anchor.id] else { return .unloaded(remaining) }

            let room = size - anchor.offset
            if remaining < room {
                anchor.offset += remaining
                return .none
            }

            remaining -= room

            switch dataSource.boundary(after: anchor.id) {
            case .item(let nextID):
                anchor = ScrollAnchor(id: nextID, offset: 0)
            case .unloaded:
                anchor.offset = size
                return .unloaded(remaining)
            case .dataEnd:
                anchor.offset = size
                return .dataEnd(remaining)
            }
        }

        return .none
    }

    private func applyBackward(_ amount: Double) -> Leftover {
        var remaining = amount

        while remaining > 0 {
            let room = anchor.offset
            if remaining <= room {
                anchor.offset -= remaining
                return .none
            }

            remaining -= room

            switch dataSource.boundary(before: anchor.id) {
            case .item(let previousID):
                guard let previousSize = sizeCache[previousID] else {
                    anchor = ScrollAnchor(id: previousID, offset: 0)
                    return .unloaded(remaining)
                }
                anchor = ScrollAnchor(id: previousID, offset: previousSize)
            case .unloaded:
                anchor.offset = 0
                return .unloaded(remaining)
            case .dataEnd:
                anchor.offset = 0
                return .dataEnd(remaining)
            }
        }

        return .none
    }
}
