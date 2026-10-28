import SwiftUI

/// Streams a scrolling `LazyGrid`: a fixed count of cross-axis tracks
/// (columns for a vertically-scrolling grid, rows for a horizontal one),
/// each item auto-placed into a cell by `GridPlacement` from its
/// `GridSpan`, with the main axis sized to content the same way
/// `FlowLayout`'s lines are.
///
/// Cross length comes straight from `tracks` (`resolveGridTracks`) — no
/// measurement involved, so no self-correction needed there, unlike every
/// other length this package tracks. Main length is different: a
/// single-cross-span item proposes a nil main length and sizes itself,
/// recorded into `rowLengths` the same way `FlowPositions` records each
/// line's tallest item. An item spanning more than one main-axis cell
/// doesn't drive any one row's height — it's proposed the *sum* of its
/// spanned rows' current best-known lengths instead, real once measured,
/// `estimatedMainLength` until then.
public struct GridLayout: StreamingLayout {
    public var tracks: [GridTrack]
    public var packing: GridPacking
    public var spacing: Double
    public var lineSpacing: Double
    public var estimatedMainLength: Double

    private let placement: GridPlacement
    private let rowLengths = GridRowLengths()

    public init(
        tracks: [GridTrack],
        axis: ScrollAxis,
        packing: GridPacking = .sparse,
        spacing: Double = 8,
        lineSpacing: Double = 8,
        estimatedMainLength: Double,
        spans: [GridSpan]
    ) {
        self.tracks = tracks
        self.packing = packing
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.estimatedMainLength = estimatedMainLength

        // `GridSpan` is always expressed in column/row terms regardless of
        // which way the grid scrolls; `GridPlacement` only knows cross/main.
        let crossSpans = spans.map { axis == .vertical ? $0.column : $0.row }
        let mainSpans = spans.map { axis == .vertical ? $0.row : $0.column }
        self.placement = GridPlacement(crossCount: tracks.count, packing: packing, crossSpans: crossSpans, mainSpans: mainSpans)
    }

    public func proposedSize(context: StreamingLayoutContext, cache: inout Void) -> ProposedViewSize {
        let cell = placement.cell(for: context.index)
        let totalCross = context.axis == .vertical ? context.viewportSize.width : context.viewportSize.height
        let crossTracks = resolveGridTracks(tracks, totalLength: totalCross, spacing: spacing)
        let crossLength = spannedTrackRange(crossTracks, start: cell.cross, span: cell.crossSpan).length

        let mainLength: CGFloat? = cell.mainSpan == 1
            ? nil
            : rowLengths.spannedLength(firstRow: cell.main, span: cell.mainSpan, lineSpacing: lineSpacing, fallback: estimatedMainLength)

        switch context.axis {
        case .vertical: return ProposedViewSize(width: crossLength, height: mainLength)
        case .horizontal: return ProposedViewSize(width: mainLength, height: crossLength)
        }
    }

    public func place(size: CGSize, context: StreamingLayoutContext, cache: inout Void) -> CGRect {
        let cell = placement.cell(for: context.index)
        let totalCross = context.axis == .vertical ? context.viewportSize.width : context.viewportSize.height
        let crossTracks = resolveGridTracks(tracks, totalLength: totalCross, spacing: spacing)
        let crossOrigin = crossTracks[cell.cross].origin
        let mainLength = context.axis == .vertical ? size.height : size.width

        rowLengths.recordMainLength(mainLength, forIndex: context.index, row: cell.main, isSingleRow: cell.mainSpan == 1)

        let globalMainOrigin = rowLengths.origin(ofRow: cell.main, lineSpacing: lineSpacing, fallback: estimatedMainLength)

        if context.neighborFrame == nil {
            rowLengths.markAnchor(at: globalMainOrigin)
        }

        // Translate from the shared, anchor-independent coordinate space
        // into one where the *current* anchor sits at local origin 0 — see
        // `MasonryLayout.place` for the same translation and why
        // it's needed.
        let mainOrigin = globalMainOrigin - rowLengths.currentAnchorOrigin

        switch context.axis {
        case .vertical: return CGRect(x: crossOrigin, y: mainOrigin, width: size.width, height: size.height)
        case .horizontal: return CGRect(x: mainOrigin, y: crossOrigin, width: size.width, height: size.height)
        }
    }

    /// Resolves every track against the widest item instead of a real
    /// proposed length: a `.px` track keeps its fixed length, an `.fr`
    /// track gets that many multiples of the widest item — an
    /// approximation (real `.fr` sizing splits *leftover* space, which
    /// doesn't exist yet with nothing proposed), but a reasonable "natural"
    /// width for content with no cross-axis constraint of its own.
    public func idealCrossLength(itemCrossLengths: [Double]) -> Double {
        guard !tracks.isEmpty else { return 0 }

        let widestItem = itemCrossLengths.max() ?? 0
        let trackLengths = tracks.map { track -> Double in
            switch track {
            case .px(let length): length
            case .fr(let weight): weight * widestItem
            }
        }

        return trackLengths.reduce(0, +) + spacing * Double(tracks.count - 1)
    }
}

/// Every row's own main-axis length, mirroring `FlowPositions`' line
/// length — self-correcting, never locked to a specific number, only
/// recomputed from whichever single-row-span item lengths are currently
/// known or estimated.
private final class GridRowLengths {
    private var rowMembers: [Int: [Int]] = [:]
    private var assignedRow: [Int: Int] = [:]
    private var lastKnownMainLength: [Int: Double] = [:]

    /// Running origin of each row already resolved, plus the fallback it
    /// was resolved with — truncated only from the row whose length just
    /// changed onward, so `origin(ofRow:)` stays O(1) amortized instead of
    /// re-summing from row 0 on every call. That re-sum used to make every
    /// `StreamingLayoutWalker` pass slower the deeper into a long list it
    /// reached, since it ran once per placed item, every walk.
    private var cachedOrigins: [Double] = [0]
    private var cachedFallback: Double?

    private(set) var currentAnchorOrigin: Double = 0

    func recordMainLength(_ length: Double, forIndex index: Int, row: Int, isSingleRow: Bool) {
        guard isSingleRow else { return }

        let previousLength = lastKnownMainLength[index]
        lastKnownMainLength[index] = length

        if assignedRow[index] == nil {
            assignedRow[index] = row
            rowMembers[row, default: []].append(index)
            invalidateOrigins(from: row)
        } else if previousLength != length {
            invalidateOrigins(from: row)
        }
    }

    func markAnchor(at origin: Double) {
        currentAnchorOrigin = origin
    }

    func length(ofRow row: Int, fallback: Double) -> Double {
        guard let members = rowMembers[row], !members.isEmpty else { return fallback }

        return members.reduce(0.0) { max($0, lastKnownMainLength[$1] ?? fallback) }
    }

    func origin(ofRow row: Int, lineSpacing: Double, fallback: Double) -> Double {
        guard row > 0 else { return 0 }

        if cachedFallback != fallback {
            cachedOrigins = [0]
            cachedFallback = fallback
        }

        while cachedOrigins.count <= row {
            let lastRow = cachedOrigins.count - 1
            cachedOrigins.append(cachedOrigins[lastRow] + length(ofRow: lastRow, fallback: fallback) + lineSpacing)
        }

        return cachedOrigins[row]
    }

    func spannedLength(firstRow: Int, span: Int, lineSpacing: Double, fallback: Double) -> Double {
        (firstRow..<(firstRow + span)).reduce(0.0) { $0 + length(ofRow: $1, fallback: fallback) } + lineSpacing * Double(span - 1)
    }

    /// `cachedOrigins[r]` depends only on rows `0..<r`, so a changed row's
    /// own cached origin is still valid — only rows after it need dropping.
    private func invalidateOrigins(from row: Int) {
        guard row + 1 < cachedOrigins.count else { return }

        cachedOrigins.removeSubrange((row + 1)...)
    }
}
