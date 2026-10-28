import SwiftUI

/// One cross-axis track's sizing rule for `LazyGrid` — a column in a
/// vertically-scrolling or fixed grid, a row in a horizontally-scrolling one.
public enum GridTrack: Equatable, Sendable {
    /// A fixed length, in points.
    case px(Double)
    /// A share of whatever space is left after every `.px` track in the same
    /// grid is subtracted — `.fr(2)` gets twice the leftover space `.fr(1)`
    /// gets. Mirrors CSS Grid's `fr` unit.
    case fr(Double)
}

/// How `LazyGrid` resolves an item's cell when it isn't given an
/// explicit one — mirrors CSS Grid's own two auto-placement algorithms.
public enum GridPacking: Sendable {
    /// Each item is placed in the first free cell at or after wherever the
    /// previous item left off — never backtracking to fill an earlier hole,
    /// so items always appear in their original order even if that leaves
    /// gaps a later, smaller item could have filled.
    case sparse
    /// Each item is placed in the first free cell overall, which can be
    /// earlier than where the previous item landed — filling holes a
    /// larger item left behind, at the cost of items no longer necessarily
    /// appearing in their original order.
    case dense
}

/// How many cells an item covers, set via `.gridSpan(column:row:)` — the
/// default (1, 1) is a single cell, same as not spanning at all.
public struct GridSpan: Equatable, Sendable {
    public var column: Int = 1
    public var row: Int = 1

    public init(column: Int = 1, row: Int = 1) {
        self.column = column
        self.row = row
    }
}

extension ContainerValues {
    @Entry var gridSpan = GridSpan()
}

/// Resolves every track's pixel origin and length along one axis: each
/// `.px` track keeps its fixed length; whatever's left of `totalLength`
/// after every `.px` track and every gap between tracks is subtracted gets
/// split among `.fr` tracks in proportion to their weight — CSS Grid's own
/// track-sizing algorithm, simplified to just these two unit types. Pure
/// function of its inputs, so unlike cell *placement* (`GridPlacement`),
/// there's nothing here that benefits from memoizing across calls.
func resolveGridTracks(_ tracks: [GridTrack], totalLength: Double, spacing: Double) -> [(origin: Double, length: Double)] {
    guard !tracks.isEmpty else { return [] }

    let pxTotal = tracks.reduce(0.0) { total, track in
        if case .px(let length) = track { return total + length }
        return total
    }
    let frTotal = tracks.reduce(0.0) { total, track in
        if case .fr(let weight) = track { return total + weight }
        return total
    }
    let gapTotal = spacing * Double(tracks.count - 1)
    let leftover = max(0, totalLength - pxTotal - gapTotal)

    var origin = 0.0
    var resolved: [(origin: Double, length: Double)] = []

    for track in tracks {
        let length: Double
        switch track {
        case .px(let fixed): length = fixed
        case .fr(let weight): length = frTotal > 0 ? leftover * (weight / frTotal) : 0
        }

        resolved.append((origin, length))
        origin += length + spacing
    }

    return resolved
}

/// The combined origin and length of a run of `span` consecutive resolved
/// tracks starting at `start` — the pixel box an item spanning that many
/// tracks covers, including the gaps between them.
func spannedTrackRange(_ tracks: [(origin: Double, length: Double)], start: Int, span: Int) -> (origin: Double, length: Double) {
    let end = min(start + span, tracks.count)
    guard start < end else { return (0, 0) }

    let last = tracks[end - 1]
    return (tracks[start].origin, (last.origin + last.length) - tracks[start].origin)
}
