/// A scroll position expressed as an item identity plus an offset within it,
/// rather than an absolute distance from the start of the content — so
/// inserting items above the anchor never moves anything already on screen.
public struct ScrollAnchor<ID: Hashable>: Equatable {
    public var id: ID
    public var offset: Double

    public init(id: ID, offset: Double = 0) {
        self.id = id
        self.offset = offset
    }
}
