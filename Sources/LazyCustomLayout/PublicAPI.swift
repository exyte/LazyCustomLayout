import SwiftUI

// MARK: - Reuse & sizing

extension View {
    /// Opts out of `LazyAnchoredScroll`'s default cell reuse, falling back
    /// to one SwiftUI identity per item.
    ///
    /// Reuse rebinds a slot's content to a different item as the window
    /// moves, so a cell's own local `@State` survives across that rebind
    /// the same way a `UITableViewCell`'s view hierarchy does — derive
    /// per-item state from the bound item itself, or reset it via
    /// `.onChange(of:)`, rather than assuming a fresh `@State` per item.
    /// Opt out here if a cell genuinely needs fresh `@State` per item
    /// instead.
    public nonisolated func cellReuse(_ enabled: Bool) -> some View {
        environment(\.cellReuseEnabled, enabled)
    }

    /// Sets how a `LazyAnchoredScroll`-based view beneath this point (any of
    /// `LazyStack`/`LazyFlow`/`LazyMasonry`/`LazyGrid`/`LazyDataGrid`) sizes
    /// itself along its scroll axis:
    /// - `.scroll` (default): hugs content up to the offered space, then
    ///   scrolls once the content is longer.
    /// - `.fitToContent`: eager and non-scrolling — every item is measured
    ///   and placed in one pass, and the view hugs the full result. Nothing
    ///   is virtualized, so only safe for content small enough to render in
    ///   full, e.g. a handful of tags in a `LazyFlow`, not a feed.
    /// - `.scrollFillingSpace`: always fills whatever space it's offered,
    ///   scrollable or not — for a full-screen feed.
    public nonisolated func lazyLayoutSizing(_ sizing: LazyLayoutSizing) -> some View {
        environment(\.lazyLayoutSizing, sizing)
    }
}

// MARK: - Grid

extension View {
    /// Marks this item as covering more than one `LazyGrid`/`LazyDataGrid`
    /// cell — read back via `subview.containerValues.gridSpan` by the
    /// grid's own auto-placement, never by this view itself.
    public nonisolated func gridSpan(column: Int = 1, row: Int = 1) -> some View {
        containerValue(\.gridSpan, GridSpan(column: column, row: row))
    }
}
