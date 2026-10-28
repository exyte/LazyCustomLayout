import SwiftUI

/// How a lazy layout (`LazyStack`, `LazyGrid`, `LazyDataGrid`, `LazyMasonry`,
/// `LazyFlow`, or `LazyAnchoredScroll` directly) sizes itself along its
/// scroll axis.
public enum LazyLayoutSizing: Equatable, Sendable {
    /// Eager and non-scrolling: every item is measured and placed in one
    /// pass through the same placement logic the lazy path uses, and the
    /// view hugs the full result. Nothing is virtualized, so only reach for
    /// this with content genuinely small enough to render in full — a
    /// handful of tags in a `LazyFlow`, not a feed.
    case fitToContent

    /// Lazy: hugs its content up to the space it's offered, then scrolls
    /// once the content is longer. Grows to the full content length if the
    /// parent proposes no length on this axis at all — the same
    /// `.fitToContent` tradeoff then applies, since nothing bounds how much
    /// gets measured. The default.
    case scroll

    /// Lazy, and always fills whatever space it's offered, scrollable or
    /// not — the behavior every lazy layout had before `.lazyLayoutSizing(_:)`
    /// existed. Reach for this for a full-screen feed.
    case scrollFillingSpace
}

extension EnvironmentValues {
    /// Exposed publicly (unlike `cellReuseEnabled`) so a custom container
    /// built the same way `LazyFlow` wraps `LazyAnchoredScroll` can read and
    /// respect it too. Set via `View.lazyLayoutSizing(_:)`.
    @Entry public var lazyLayoutSizing: LazyLayoutSizing = .scroll
}
