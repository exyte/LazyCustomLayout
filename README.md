<a href="https://exyte.com/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/exyte/media/master/common/header-dark.png"><img src="https://raw.githubusercontent.com/exyte/media/master/common/header-light.png"></picture></a>

<table>
    <thead>
        <tr>
            <th width="25%">Masonry</th>
            <th width="25%">Heavy grid</th>
            <th width="25%">Grid Spans</th>
            <th width="25%">Flow</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td width="25%">
                <img width="100%" src="https://github.com/user-attachments/assets/ae559457-b419-4784-a952-018efd398f60" />
            </td>
            <td width="25%">
                <img width="100%" src="https://github.com/user-attachments/assets/821ca602-33e3-4f3e-b485-182311049932" />
            </td>
            <td width="25%">
                <img width="100%" src="https://github.com/user-attachments/assets/44f0a10b-7892-4714-a9d3-db0959b56a2d" />
            </td>
            <td width="25%">
                <img width="100%" src="https://github.com/user-attachments/assets/4a66e176-182b-4a5d-bf46-a97f93fd2361" />
            </td>
        </tr>
    </tbody>
</table>

<img align="right" width="160" alt="Demo" src="https://github.com/user-attachments/assets/6846759e-19da-489f-a02d-53a87063eb06" />

<p><h1 align="left">Lazy Custom Layout</h1></p>

<p><h4>A lazy, anchor-based scroll engine for SwiftUI — stream any custom layout (masonry, flow, grid, table...) without ever measuring the whole collection up front</h4></p>

![](https://img.shields.io/github/v/tag/exyte/LazyCustomLayout?label=Version)
[![SPM](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-black.svg)](https://opensource.org/licenses/MIT)


# Usage

The simplest way to use the library is one of the built-in `LazySmth` views, e.g. a masonry grid:

```swift
import LazyCustomLayout

LazyMasonry(0..<300, lanes: 2, spacing: 8, estimatedItemLength: 160) { index in
    Tile(index: index)
}
```

`estimatedItemLength` is just a guess used to decide how many items to measure before a real size comes in — doesn't need to be accurate, only roughly right.

# Scrolling engine

`LazyAnchoredScroll`/`AnchoredScrollView` don't use `UIScrollView`. A `UIScrollView` (and `LazyVStack`/`LazyVGrid` on top of it) tracks an absolute `contentOffset` against a total `contentSize` — so a lazy container has to estimate that total size up front and keep correcting it as real item sizes stream in. That's the jump you see when content loads above the visible area, and why fully custom column widths aren't supported.

Instead, we track an anchor: *(item id, offset within that item)*. Nothing on screen is positioned relative to the start of the content, only relative to its own anchor — so there's never a total size to know, estimate, or correct. That's what makes true laziness possible for an arbitrary custom layout, not just the handful UIKit/SwiftUI ship built in. Physics and gestures (pan, deceleration, rubber-banding) are reimplemented on top of this model rather than borrowed from `UIScrollView`.

For a simple table, this is just `LazyStack`:

```swift
LazyStack(0..<2000, spacing: 1, estimatedItemLength: 60, maxLoadedItems: 30) { index in
    TableRow(index: index)
}
```

`maxLoadedItems` caps how many rows are ever instantiated at once, regardless of buffer distance — useful for heavy rows.

# Sizing

Every `LazySmth` view (and `LazyAnchoredScroll` directly) sizes itself along its scroll axis via `.lazyLayoutSizing(_:)`:

```swift
LazyFlow(tags, spacing: 6, lineSpacing: 6, estimatedItemLength: 60) { tag in Chip(tag) }
    .lazyLayoutSizing(.fitToContent)
```

- **`.scroll`** (default) — hugs its content up to the space it's offered, then scrolls once content overflows. Grows to the full content length if the parent proposes no length on this axis at all.
- **`.fitToContent`** — eager and non-scrolling: every item is measured and placed in one pass, and the view hugs the full result. Only reach for this with content genuinely small enough to render in full, e.g. a handful of tags in a card — not a feed.
- **`.scrollFillingSpace`** — always fills whatever space it's offered, scrollable or not. The behavior every lazy layout had before `.lazyLayoutSizing(_:)` existed; reach for this for a full-screen feed.

# The `StreamingLayout` protocol

Shaped like SwiftUI's own `Layout`, propose → measure → place, but asked about **one item at a time** instead of the whole collection — so a custom layout only ever needs to know about a small window around the anchor, never every item.

```swift
struct PagingLayout: StreamingLayout {
    func proposedSize(context: StreamingLayoutContext, cache: inout Void) -> ProposedViewSize {
        ProposedViewSize(context.viewportSize)
    }

    func place(size: CGSize, context: StreamingLayoutContext, cache: inout Void) -> CGRect {
        let origin = context.direction == .forward
            ? (context.neighborFrame?.maxY ?? 0)
            : (context.neighborFrame?.minY ?? 0) - size.height
        return CGRect(x: 0, y: origin, width: size.width, height: size.height)
    }
}
```

`place` gets the already-placed neighbor's frame (`context.neighborFrame`, `nil` for the anchor item itself) and returns this item's frame right next to it — everything else (identifying the window, caching sizes, translating into on-screen offsets) is handled for you by `LazyAnchoredScroll`, which any `StreamingLayout` plugs straight into:

```swift
LazyAnchoredScroll(data, layout: PagingLayout(), estimatedItemLength: ...) { item in ItemView(item) }
```

# Built-in layouts

Each one is a folder with (at least) two files: the `SmthLayout` itself — the `StreamingLayout` conformance — and `LazySmth`, a one-line wrapper around `LazyAnchoredScroll(layout: SmthLayout(...))`.

- **`StackLayout`** / **`LazyStack`** — one column/row, each item sized to itself. Simplest layout, good for tables and lists.
- **`MasonryLayout`** / **`LazyMasonry`** — N equal-width lanes, each item going into whichever lane is currently shortest. Pinterest-style grid:
  ```swift
  LazyMasonry(items, lanes: 2, spacing: 8, estimatedItemLength: 160) { item in TileView(item) }
  ```
- **`FlowLayout`** / **`LazyFlow`** — variable-width items wrap left-to-right once the current line runs out of room. Tag cloud:
  ```swift
  LazyFlow(words, spacing: 8, lineSpacing: 10, estimatedItemLength: 44) { word in Chip(word) }
  ```
- **`GridLayout`** / **`LazyGrid`** — CSS-Grid-style auto-placement over fixed (`.px`) or proportional (`.fr`) tracks, with multi-cell spans. `LazyGrid` takes `columns:`/`rows:` to scroll one axis, or both to get a fixed, non-scrolling grid:
  ```swift
  LazyGrid(columns: 3, spacing: 12, estimatedRowLength: 130) {
      ForEach(0..<300) { index in GridTile(index) }
  }
  ```
- **`AnchoredScrollView`** — not a `StreamingLayout`, so no `SmthLayout`/`LazySmth` pair: the same scroll engine applied to one eagerly-rendered piece of content with nothing to window. Use this when there's no collection, just `AnchoredScrollView { content }`.

## Example project

`LazyCustomLayoutExample/LazyCustomLayoutExample.xcodeproj` has one screen per layout above, plus a side-by-side comparison against `ScrollView`.

## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

```swift
dependencies: [
    .package(url: "https://github.com/exyte/LazyCustomLayout.git")
]
```

## Requirements

* iOS 18.0+

## Our other open source SwiftUI libraries
[AnchoredPopup](https://github.com/exyte/AnchoredPopup) - Popup that grows "out" of a trigger view, anchored to it   
[PopupView](https://github.com/exyte/PopupView) - Toasts and popups library    
[Grid](https://github.com/exyte/Grid) - The most powerful Grid container     
[AnimatedTabBar](https://github.com/exyte/AnimatedTabBar) - A tabbar with a number of preset animations   
[ScalingHeaderScrollView](https://github.com/exyte/ScalingHeaderScrollView) - A scroll view with a sticky header which shrinks as you scroll  
[MediaPicker](https://github.com/exyte/mediapicker) - Customizable media picker     
[Chat](https://github.com/exyte/chat) - Chat UI framework with fully customizable message cells, input view, and a built-in media picker  
[CalendarView](https://github.com/exyte/CalendarView) - Calendar view with fully customizable month/day cells     
[AnimatedGradient](https://github.com/exyte/AnimatedGradient) - Animated linear gradient     
[ConcentricOnboarding](https://github.com/exyte/ConcentricOnboarding) - Animated onboarding flow    
[FloatingButton](https://github.com/exyte/FloatingButton) - Floating button menu    
[ActivityIndicatorView](https://github.com/exyte/ActivityIndicatorView) - A number of animated loading indicators    
[ProgressIndicatorView](https://github.com/exyte/ProgressIndicatorView) - A number of animated progress indicators    
[FlagAndCountryCode](https://github.com/exyte/FlagAndCountryCode) - Phone codes and flags for every country    
