# Design notes

This file exists so a future session (human or Claude) can pick this project
back up without re-deriving the reasoning behind it. It's a summary of the
conversation that led to this code, not API documentation — see the README
for that once it exists.

## The problem

SwiftUI's `Layout` protocol and `UIScrollView` solve different halves of
"lazy custom layout," and neither solves both:

- **`Layout` is eager.** `sizeThatFits`/`placeSubviews` receive every subview
  up front — SwiftUI has already expanded the `ForEach` before your code
  runs. There's no hook to say "give me item *k* only when I need it," so you
  can't build a custom layout (flow, staggered/masonry, etc.) that's also
  lazy. `LazyVStack`/`LazyVGrid` get their laziness from private SwiftUI
  internals, not from anything exposed through `Layout`.
- **`UIScrollView` (and everything built on it) uses an absolute offset
  against a total content size.** A lazy container therefore has to estimate
  the total size up front and keep correcting it as real item sizes stream
  in — that's the source of the familiar jump when content loads above the
  visible area, unreliable `scrollTo`, and why grids mostly only support
  fixed or adaptive column widths (sizing a column to its widest cell needs
  every cell, which breaks laziness the same way `Layout` does).

The fix we landed on: replace the absolute offset with an **anchor** —
*(item id, offset within that item)* — the same idea Compose's `LazyListState`
uses, but keyed by id instead of index so inserting items above the visible
window never moves anything on screen. On top of that, a **streaming layout**
protocol, deliberately shaped like SwiftUI's own `Layout` (propose a size,
measure, place), but asked about one item at a time instead of the whole
collection at once, so only a window of items around the anchor needs to be
alive — loading further in both directions as needed.

## Decisions made along the way

- **Fully custom scroll physics, not a hidden `UIScrollView`.** The
  alternative — a real `UIScrollView` underneath purely for physics/gestures,
  with its absolute offset never treated as meaningful — would have kept
  Liquid Glass scroll-edge effects, bars that minimize on scroll, status-bar
  tap-to-scroll-to-top, and native nested-scroll handoff for free. We chose
  the fully custom route anyway, for full control over the physics and no
  dependency on UIKit's internals. Known, accepted cost: all of the above
  need to be rebuilt by hand or are simply not supported; see `ScrollGesture.swift`'s
  `Coordinator` for the edge-swipe-back heuristic as an example of that cost.
- **One package, not two.** This briefly existed as two packages, merged back
  into one on request. **Consequence**: `swift test` doesn't work standalone
  from the shell once any file imports UIKit (`ScrollGesture.swift` does).
  Verify compilation instead with
  `swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --triple arm64-apple-ios18.0-simulator --build-tests`;
  actually *running* the tests needs a real simulator session (open in Xcode
  and run there), since the scheme's test plan still isn't wired to a
  simulator destination — same caveat as before, still unresolved.
- **Rubber-banding lives inside the engine, not the anchor model.** The
  engine tracks an internal `overscroll` (honest, pre-rubber-band distance
  past an edge) and asks its delegate for remaining "slack" only while *not*
  overscrolled. This keeps the engine's delegate contract tiny
  (`viewportLength`, `slack(direction:)`) — it doesn't need to know about
  content size or scroll position at all. **Consequence discovered later**:
  anything that sits between the engine and the anchor must preserve this
  split itself. `LazyAnchoredScrollController` originally routed the
  engine's overscroll deltas straight through `AnchorResolver`, which
  structurally clamps at the true start/end and silently discards whatever
  it can't resolve — so a rubber-band stretch at the top of a list vanished
  into nothing, while the engine still thought it owed a spring bounce-back
  once released, which then landed as a real forward anchor move (observed
  as "pulling down at the top jumps forward into later rows" instead of
  resisting). Fixed by giving the controller its own `overscrollOffset`
  scalar, mirroring the engine's own honest-vs-overscroll split one layer up,
  and only ever handing `AnchorResolver` the *honest* portion of a delta.
- **Public views need zero manual setup.** Cross-project rule (now in the
  user's global `~/.claude/CLAUDE.md`, not repeated per-project): a public
  SwiftUI view must work as one line with no required caller setup — never
  `@State private var controller = SomeController(...)` in caller code. This
  is why `AnchoredScrollView` and `LazyAnchoredScroll` both own their
  controller internally (`SingleContentScrollController` /
  `LazyAnchoredScrollController`), created in `init`, never exposed.
- **`StreamingLayout` mirrors `Layout`'s propose → measure → place shape**,
  not the original bespoke scalar protocol. `proposedSize(context:cache:)`
  returns a real `ProposedViewSize`; `place(size:context:cache:)` returns a
  real `CGRect`. `StreamingLayoutContext` carries everything a conformer
  might need (axis, direction, index, item count, the current anchor,
  viewport size, the already-placed neighbor) so it has the same information
  `Layout` would get via `bounds`/`proposal`/`subviews`, just for one
  streamed item instead of the whole collection. `Cache` mirrors `Layout.Cache`
  (no `updateCache` — a window is always walked fresh, never incrementally
  updated, so there's nothing to keep a long-lived cache in sync with).
- **Masonry needed two iterations to get the lane/position stability right**
  — worth recording precisely since the bug was subtle and the fix is easy to
  accidentally re-break:
  - **v1 (lane-only persistence)**: each item's "shortest lane" choice was
    recomputed from scratch on every render. As a not-yet-measured neighbor's
    estimated size got replaced by its real one, the lane balance could flip,
    visibly hopping an already-settled tile between columns. Fixed by
    permanently remembering each item's lane the first time it's computed
    (in a small reference type shared across every copy of the layout
    struct), never recomputing it.
  - **v2 (lane *and* position persistence — wrong)**: tried permanently
    locking each item's *origin* too, to stop the other bug (below). This
    was wrong: the first time an item is seen, its real size usually isn't
    known yet, so whatever estimate was used to advance that lane's frontier
    at that moment got baked in forever. The moment the real size arrived,
    the *next* item in that lane was left at a permanently wrong offset — a
    gap or overlap that could never self-correct, unlike every other layout
    in this package. Confirmed directly (not by guessing): the same two
    tiles, scrolled to twice in a row, showed a large gap once and none the
    next time — only possible if something was being computed inconsistently.
  - **v3 (current)**: lane stays permanent (v1's fix, correct). Position is
    *not* locked — it's recomputed on every call as the sum of every
    smaller-index item's current best-known length within the same lane
    (real `SizeCache` value once measured, estimate until then), exactly the
    same self-correcting approach `StackStreamingLayout` already used. What's
    persisted is only *which indices belong to which lane*, never a specific
    numeric offset. See `MasonryLayout.swift`'s doc comment and
    `MasonryPositions` for the implementation; this is exactly the mitigation
    DESIGN.md had originally sketched ("cache each item's row/lane assignment
    by id once computed") — it just took a wrong detour through "cache the
    position too" before landing there.
  - This was found via a real device recording (not synthetic test gestures),
    and the fix was verified the same way: scrolling back and forth over the
    same two tiles repeatedly and confirming the gap no longer appears either
    way. There is **no automated test for this** yet — see "What's next."
- **Known, accepted seams** (same spirit as the masonry note above, smaller):
  - ~~`FlowStreamingLayout` only supports a *fixed* `itemLength`~~ — resolved
    in a later session; see "Variable-width Flow, the Grid system, and a
    two-location alignment bug" below. `SizeCache` gained a cross-axis
    counterpart (`crossSizeCache`), which is what made this possible.
  - `MasonryLayout`'s lane assignment for a never-before-seen
    anchor (big `scrollTo` jump, or a single engine tick fast enough to skip
    unrendered items) uses whichever lane is currently shortest rather than
    the item's "true" neighbors. (`FlowStreamingLayout` no longer has the
    equivalent seam — see the anchor-resolution session below; its line
    membership is now a pure function of index, not something walked
    forward/backward from the anchor at all.)
  - Negative/degenerate container sizes during a navigation push's
    transition (before the real size settles) are clamped to zero in both
    `MasonryLayout.laneLength` and the calculator's cell-size math
    — without the clamp, SwiftUI logs "Invalid frame dimension" faults
    during the push animation.
- **A later session found `AnchorResolver`'s core assumption was wrong for
  every non-`Stack` layout, in three successive layers** — worth recording
  in full since each fix looked complete and verified on-device, and wasn't:
  - **The trigger**: a user-reported "masonry jerk" — on real touch
    scrolling (never reproduced by a scripted drag at first), every visible
    tile would occasionally snap by a large, inconsistent amount. Diagnosed
    by adding a temporary debug print of every on-screen item's resolved
    frame and diffing consecutive lines, per the user's own suggestion —
    this is the technique to reach for first next time a position bug
    resists a scripted repro; guessing from reading the code burned real
    turns here before the user redirected to "just add prints."
  - **Root cause #1 (masonry)**: `AnchorResolver.applyForward`/`applyBackward`
    (`Anchor/AnchorResolver.swift`) advance from item `id` to `id + 1` by
    treating `sizeCache[id]` — that item's own rendered length — as the
    scroll-axis distance to the next item. True only for a single sequential
    column (`StackStreamingLayout`); false the instant two items can sit
    side by side (masonry's lanes), where the "next" index can even start
    *behind* the current one. Every lane-crossing boundary produced a jump
    by however wrong that guess was (confirmed: ~230pt on a 182pt-tall tile).
  - **Fix attempt #1**: keep `AnchorResolver` itself untouched (it's
    deliberately layout-agnostic and has its own passing tests); in
    `LazyAnchoredScrollController.applyEngineDelta`, snapshot the
    `StreamingLayoutWindow` relative to the pre-delta anchor, and if the
    resolver changed `anchor.id`, patch just its `offset` using that
    window's real frame for the new id. Verified on-device (diffed hundreds
    of frames, zero discontinuities across several boundary crossings) and
    reported fixed.
  - **Regression from fix #1**: patching only `offset` while keeping
    whatever `id` the resolver guessed can leave that offset outside the
    id's own `[0, length)` range — an invariant `AnchorResolver`'s *next*
    call silently assumes. A later unrelated scroll then double-applies the
    corruption: `room = size - offset` goes negative, the walk "succeeds"
    without ever detecting it ran off the true start, and lands back at item
    0 — the user saw this as "keeps resetting me to the first item, leaving
    blank space on top." Fixed by re-deriving *both* id and offset together
    (search the pre-delta window for whichever item's frame truly contains
    the target local position — the one with the largest origin at or before
    it, guaranteeing a non-negative offset by construction) instead of
    patching the resolver's own guess.
  - **Root cause #2 (flow), found testing the same fix on `FlowExample`**:
    `FlowStreamingLayout`'s rewrite (done in this same session — see the
    `Known, accepted seams` note above) computed each tile's position in a
    *global* coordinate space (distance from true index 0) but never
    translated into the anchor-relative local space the rest of the system
    requires, the one thing `MasonryLayout` does via
    `currentAnchorOrigin`. It only looked correct in the first on-device
    verification because the anchor happened to still be at index 0, whose
    global and local origin coincide; advancing the anchor to a later line
    exposed it as scrambled positions. Fixed by adding the same
    `currentAnchorOrigin` subtraction masonry already had.
  - **Root cause #3 (edges, found testing reversal on flow)**:
    `AnchorResolver`'s own `.dataEnd` detection *also* uses each item's raw
    length as the edge-distance proxy, so near the true start/end of a
    multi-item-per-line layout it can think there's still room when there
    isn't — a large reversal fling computed as "still fits, lands at item 0"
    when the true geometry had already run off the start partway through
    that delta, silently swallowing what should have been rubber-band
    overscroll instead of firing `onReachStart`. Fixed by clamping the delta
    to the window's own correctly-computed forward/backward slack *before*
    handing it to the resolver, reporting any excess as `.dataEnd` directly.
  - **The architecture smell, called out by the user**: after root causes
    #1–#3, the fix lived as a `correctAnchor` method on `ScrollPositionState`
    that `LazyAnchoredScrollController` called from outside, right after its
    own `applyDelta` — the storage/mutation split the type was designed
    around ended up with the *geometry-aware* half of "apply a delta" in a
    different type than the half deciding whether a boundary was crossed at
    all. Refactored into a new `StreamingAnchorPositionState`
    (`Lazy/StreamingAnchorPositionState.swift`) that owns the whole
    operation — window computation, slack clamping, and id/offset
    correction all happen inside its own `applyDelta`, wrapping a plain
    `ScrollPositionState<ArrayIndexDataSource>` internally for the parts
    that generic walk already gets right (data-end callbacks,
    `scrollTo`/`animateScrollTo`). `LazyAnchoredScrollController` went back
    to exactly its pre-bug shape: call `streamingAnchor.applyDelta(delta)`,
    switch on a plain `Leftover`. During that refactor, `correctAnchor`
    itself turned out to be dead weight — it duplicated what the already-
    public `scrollTo(id:offset:)` did (`resolver.setAnchor` + re-sync
    `anchor`), including the free benefit of cancelling any in-flight
    `animateScrollTo` spring, which is the right behavior for a live drag
    anyway. Removed in favor of calling `scrollTo` directly.
  - **Still open**: `animateScrollTo`'s own distance resolution
    (`ScrollPositionState.resolveForwardDistance`/`resolveBackwardDistance`)
    inherits the *exact* same per-item-length-summing assumption root cause
    #1 had — unexercised by any example screen yet (no "jump to item N" UI
    exists — see "What's next"), so not yet confirmed broken in practice,
    but should be assumed wrong for masonry/flow until it's fixed the same
    way `applyDelta` was. **No automated test covers any of this** — see
    "What's next."

- **Variable-width Flow, the Grid system, and a two-location alignment bug**
  — a later session, requested as two features ("flow should wrap
  variable-width tags, not fixed tiles" and "a CSS-Grid-style lazy
  `AnchoredGrid` with `.px`/`.fr` tracks, spans, and sparse/dense
  auto-placement"), that turned up a real, previously-latent bug in
  `LazyAnchoredScroll` itself along the way:
  - **Cross-axis plumbing.** `SizeCache` stayed scroll-axis-only; a second
    instance (`crossSizeCache`) was added to `LazyAnchoredScrollController`,
    fed by `LazyAnchoredScroll`'s `.measuringSize` callback writing *both*
    dimensions, and consulted by `streamingLayoutWindow`'s `resolvedSize`
    whenever a layout proposes a nil cross length (meaning "size yourself").
    Every existing layout always proposed a concrete cross length, so this
    is additive — nothing about Stack/Masonry's behavior changed.
  - **Flow's line-wrapping rewrite** (`FlowStreamingLayout`): dropped the
    fixed `itemLength`; a line's membership is now a greedy, CSS-flex-wrap
    sweep over each item's real-or-estimated cross length, continuing from
    wherever it last stopped (`FlowPositions.sweep`). First attempt made
    this permanent, copying masonry's lane-choice precedent — **wrong**:
    unlike a lane choice, a wrong line guess doesn't just unbalance
    something, it overflows the viewport, and since *every* first-ever
    render estimates cross length as `estimatedItemLength` (a value tuned
    for the scroll axis, with no relationship to how wide a word actually
    is), the very first screen's lines were reliably ~2x too full,
    overflowing visibly on nearly every line, every time — confirmed via a
    real device run (last chip in a row routinely 30-80pt past the right
    edge) before being caught, not a rare edge case. Fixed by making line
    membership self-correcting instead: when an item's real cross length
    disagrees with the guess its line was built from, rewind to that line's
    *first* member and replay forward — bounded to that one line onward,
    never back to index 0, since a line's membership only ever depends on
    earlier items, never later ones.
  - **The actual `LazyAnchoredScroll` bug, found while chasing what looked
    like a Flow-only rendering glitch**: a horizontal-axis `AnchoredGrid`
    (the `rows:` case) was silently dropping its last row. `GridStreamingLayout`'s
    own computed frames were confirmed correct by temporary debug prints
    (the standard technique here — see the anchor-resolution saga above)
    for every single item, so the bug wasn't in `Grid/` at all: `LazyAnchoredScroll.body`
    had `ZStack(alignment: axis == .vertical ? .topLeading : .leading)`,
    repeated on the `.frame(...)` right after it. Every child is placed via
    `.offset`, which — unlike `.position` — never feeds into a container's
    own computed size, so the ZStack's "natural" size was just one item's
    frame, not the full laid-out content. `.topLeading` happens to be inert
    against that (top and leading both pin to an edge regardless), which is
    why no vertical-axis screen (the only kind this package had before) ever
    exposed it; `.leading` is `Alignment(horizontal: .leading, vertical: .center)`,
    so for a horizontal axis the undersized ZStack got vertically *centered*
    inside its `.frame`, shifting every row down by the same amount, and the
    outer `.frame(...).clipped()` cut off whatever that shift pushed past
    the bottom — exactly the missing last row. Fixed in both places by
    hardcoding `.topLeading` unconditionally; axis never needs anything
    else, since the cross axis is always meant to start flush and the main
    axis is always offset explicitly per item regardless of scroll direction.
  - **A smaller fix bundled into the same pass**: `LazyAnchoredScroll`'s
    original "two frames" measuring technique (propose the layout's nil
    dimension, measure, then re-pin to the walker's stable frame) assumed a
    nil/nil proposal (needed once Flow's cross axis became variable too)
    would let content report its natural size. It doesn't: a `.frame(width:
    nil, height: nil)` has nothing of its own to redefine the incoming
    proposal with, so with the *outer* re-pinning frame sitting further out
    in the same chain, the ambient proposal passed straight through
    instead — every first-ever Flow chip measured at exactly
    `estimatedItemLength` square, with its text visibly truncated to 1-3
    characters, confirmed via a temporary print showing every single index
    measuring identically. `.fixedSize(horizontal:vertical:)`, inserted
    right after the inner proposal-frame, doesn't have this problem — it's
    documented to force an ideal measurement regardless of ambient
    proposal — so it's now applied for exactly the dimensions a layout's
    `proposedSize` leaves nil.
  - **`AnchoredGrid`'s own design**: unlike every length this package
    tracks, where an item goes (`GridPlacement`'s sparse/dense
    auto-placement) is a pure function of every earlier item's *span*,
    never its size — spans don't change after being read, so this sweep is
    exact, not a self-correcting seam the way Flow's line membership or
    masonry's position is. Only track *lengths* depend on measurement (an
    auto-sized main axis, mirroring `FlowPositions`'s line-length tracking
    — see `GridStreamingLayout`'s `GridRowLengths`), which is the only
    reason the scrolling cases need `LazyAnchoredScroll` at all. The fixed
    (`columns:` and `rows:` both given) case doesn't stream anything —
    nothing to be lazy about once every item is always on screen — so it
    skips `StreamingLayout` entirely and resolves both axes' tracks
    directly against whatever size it's given (`AnchoredGrid.swift`'s
    private `FixedAnchoredGrid`), the same non-lazy spirit as
    `CalculatorExample`'s original hand-built layout, which it replaced.
  - **Identity, for the calculator's mode-switch animation to survive the
    move to `AnchoredGrid`**: `LazyAnchoredScroll` keyed its rendering
    `ForEach` by raw array index, which is fine for a dataset whose order
    never changes but wrong the instant it can (`AnchoredGrid` re-placing
    the same subviews into different cells when the calculator's mode
    changes) — position-keyed identity reads as "whatever's at slot N",
    so a reorder cross-dissolves instead of each button animating to its
    new spot. Added an optional `id:` closure (default: index, unchanged
    for every existing caller) that `AnchoredGrid` feeds with each
    `Subview`'s own stable `.id`.

## What exists right now

**`Sources/AnchoredScroll/`** — one package, one target. Builds clean for iOS
via `swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --triple arm64-apple-ios18.0-simulator`:

- **`Engine/`** — `ScrollPhysics` (deceleration, rubber-band curve, critically
  damped spring), `VelocityTracker`, `FrameDriving`/`FrameClock`, `ScrollEngine`
  (the `idle`/`dragging`/`flinging`/`springing` state machine — no absolute
  position, no content size, just a stream of deltas), `ScrollDragGesture`/
  `ScrollTouchDownGesture`. Tuned on-device (Phase 1's original "yours to do"
  item is done): fling weight, rubber-band, the touch-down interrupt, and the
  edge-swipe-back deference width all confirmed to feel right on the
  simulator; the only bug found and fixed in this layer was the overscroll
  one described above.
- **`Anchor/`** — `ScrollAnchor` (id + offset), `AnchorResolver` (walks a
  delta across item boundaries using measured sizes, reports unresolved
  leftover as `.dataEnd` at the true data ends or `.unloaded` mid-data),
  `SizeCache` (`@Observable`, id → measured length, survives unloading),
  public `ScrollPositionState` (`scrollTo`/`animateScrollTo`,
  `onReachStart`/`onReachEnd`). **Not yet exercised by any example screen**
  (no "jump to item N" UI built) — the lazy table/masonry/flow screens use
  the anchor model under the hood but never call `scrollTo`/`animateScrollTo`
  directly.
- **`Layout/`** — the `StreamingLayout` protocol and its conformers:
  - `StreamingLayout` protocol + `StreamingLayoutContext` + `StreamingLayoutWalker`
    (the pure function that walks a layout outward from the anchor, forward
    and backward, producing the render window + frames + rubber-band slack —
    computed fresh on every layout pass and every slack query).
  - `StackStreamingLayout` — single column/row, the simplest conformer.
  - `MasonryLayout` — masonry; see the v1→v2→v3 note above.
  - `FlowStreamingLayout` — variable-width tags wrapping to fill the width,
    like a tag cloud. Line membership is a self-correcting greedy sweep
    (`FlowPositions.sweep`), not a pure function of index the way a
    fixed-width flow's was — see "Variable-width Flow, the Grid system, and
    a two-location alignment bug" above for the full story, including the
    v1 (permanent, wrong) attempt. What's remembered, the same reason
    masonry remembers each item's lane, is each line's own main-axis length
    (the tallest item placed in it so far) — see `FlowPositions` in the same
    file.
- **`Lazy/`** — wiring a `StreamingLayout` up to the anchor model and the
  scroll engine:
  - `StreamingAnchorPositionState` (internal) — owns a `LazyAnchoredScroll`'s
    anchor, resolving deltas against the active `layout`'s real geometry
    instead of `AnchorResolver`'s generic per-item-length walk. Wraps a plain
    `ScrollPositionState<ArrayIndexDataSource>` for the parts that generic
    walk already gets right (data-end detection, `onReachStart`/
    `onReachEnd`, `scrollTo`/`animateScrollTo`) and corrects only the
    (id, offset) it lands on. See the anchor-resolution note above for why
    this type exists and what it replaced.
  - `LazyAnchoredScroll` (public view) + `LazyAnchoredScrollController`
    (internal) — the lazy container itself. Caller-configurable `bufferLength`
    (how far past the viewport to keep loaded, each direction; `nil` = one
    extra viewport) and `maxLoadedItems` (hard cap on in-memory item count,
    independent of distance) — both requested explicitly as "control how
    many items are in memory." The controller itself is now thin: it owns a
    `StreamingAnchorPositionState` and the drag/fling `ScrollEngine`, and
    `applyEngineDelta` just forwards to the former and switches on a plain
    `Leftover` — all the geometry-aware resolution lives in that type, not
    here.
- **`Grid/`** — the CSS-Grid-style container, see the design note above for
  the reasoning behind each piece:
  - `GridTrack` (`.px`/`.fr`), `GridPacking` (`.sparse`/`.dense`), `GridSpan`
    + the `.gridSpan(column:row:)` modifier (backed by a `ContainerValues`
    entry, read back via `Group(subviews:)`), and `resolveGridTracks`/
    `spannedTrackRange` — pure, stateless track-sizing helpers, no
    measurement or memoization needed since track lengths never depend on
    content.
  - `GridPlacement` (internal) — the sparse/dense auto-placement engine,
    axis-agnostic (`cross`/`main`, not `column`/`row`), shared by both the
    scrolling and fixed cases.
  - `GridStreamingLayout` (public) — the `StreamingLayout` conformer for the
    scrolling cases (`columns:` or `rows:` alone); owns a `GridRowLengths`
    for the auto-sized main axis, mirroring `FlowPositions`'s line-length
    tracking.
  - `AnchoredGrid` (public view) — five initializers (`columns:`/`rows:` as
    either `Int` or `[GridTrack]`, plus `columns:rows:` together for the
    fixed case) all funneling into one private canonical init. `FixedAnchoredGrid`
    (private) handles the fixed case directly, no `LazyAnchoredScroll`
    involved.
- **`AnchoredScrollView`** (public) + `SingleContentScrollController`
  (internal) — the non-lazy, single-content counterpart; `ScrollView`-style
  zero-setup API, no anchor model needed since there's only one piece of
  content.
- **`ScrollAxis`, `MeasuringLength`/`measuringSize`** — small shared helpers.

**`Tests/AnchoredScrollTests/`** — covers `ScrollPhysics`, `VelocityTracker`,
`ScrollEngine` (Phase 1) and `AnchorResolver`, `ScrollPositionState` (Phase 2),
using fakes (`FakeFrameDriving`, `FakeScrollEngineDelegate`,
`FakeAnchorDataSource`); `GridPlacementTests` (sparse/dense packing, including
both calculator `GridSlot` tables reproduced exactly, plus `resolveGridTracks`)
and `FlowLineBreakTests` (wrapping, same-line spacing, anchor-relative
translation) from the Grid/variable-Flow session. **Still no tests for
`StreamingLayoutWalker`, the other layouts, or `StreamingAnchorPositionState`/
either controller** — that gap is the sharpest one now: `AnchorResolver`'s own
tests only exercise its single-sequential-column assumption, which is exactly
the assumption three separate bugs in the anchor-resolution saga (see above)
came from violating — none of which those tests could have caught, since
`StreamingAnchorPositionState` (where the real fix lives) has no tests of its
own at all yet. Known not-yet-confirmed-passing either way: running the
existing suite still needs the test-plan-wiring fix mentioned above (`GetTestList`
reports 0 tests in the active test plan); `swift build --build-tests` is the
only confirmed-working verification path.

**`AnchoredScrollExample/`** — `xcodegen`-generated (`project.yml`; re-run
`xcodegen generate` after adding/removing source files). Screens, from
`MainView`:

- `VerticalScrollExample`, `HorizontalScrollExample`,
  `CompareWithScrollViewExample` — Phase 1, using `AnchoredScrollView`.
- `TableExample` — `LazyAnchoredScroll` + `StackStreamingLayout`,
  2,000 variable-height rows, `maxLoadedItems: 30` demonstrated. (Every
  `AnchoredScroll` layout streams regardless of item count, so there's no
  separate "lazy" mode to call out by name.)
- `MasonryExample` — `MasonryLayout`, 2 lanes, 300 tiles.
- `FlowExample` — `FlowStreamingLayout`, a word tag cloud (`LoremText`),
  variable-width chips wrapping like a paragraph.
- `GridExample` — `AnchoredGrid`, a segmented control across four
  representative layouts: a 3-equal-column scrolling grid (300 square
  tiles), a horizontally-scrolling `rows:` grid with 20 numbered, variably-
  sized tiles to trace the auto-placement order, a `columns:` grid mixing
  `.px` and `.fr` tracks, and the `[.fr(1), .px(150), .fr(2)]` +
  `.gridSpan` + `.dense` mosaic.
- `CalculatorExample` — now built on `AnchoredGrid(columns:rows:)` (its
  fixed, non-scrolling mode) instead of a hand-built `GeometryReader`/`ZStack`.
  Two arrangements ("System": standard 4×5 grid; "Alternative": 5×5 with a
  tall "+" and wide "="), switched via a segmented control. `CalculatorMode`
  expresses each arrangement as an ordered button list + per-button
  `GridSpan` instead of explicit `(column, row)` coordinates — sparse
  auto-placement over that order reproduces both original hand-placed
  layouts exactly (verified by hand-tracing both, then confirmed by
  `GridPlacementTests`). Every button keeps stable identity (`CalculatorButton`
  enum, used as the `ForEach` id, threaded through to each auto-placed
  `Subview`'s own identity via `LazyAnchoredScroll`'s `id:` — see the design
  note above) across the switch so SwiftUI animates each one to its new slot
  instead of cross-dissolving. Verified the animation actually plays (not
  just snapping) by temporarily slowing it to 3 seconds and catching a real
  mid-transition frame showing buttons mid-slide/mid-resize.

Builds clean; all of the above verified on-device (simulator), not on a
physical device.

## What's next

Roughly in priority order:

1. **Tests for everything under `Lazy/`, especially `StreamingAnchorPositionState`.**
   This is the most concrete lesson from this session, twice over: the
   masonry position bug *and* the later anchor-resolution saga each went
   through a fix that looked plausible and verified clean on-device, then
   turned out wrong in a way only a further round of manual device testing
   caught. A fake-layout unit test for `StreamingAnchorPositionState.applyDelta`
   — items deliberately placed out of index order (simulating masonry lanes
   / flow lines), asserting that applying a sequence of deltas always lands
   on an id+offset whose resolved frame actually contains the expected
   scroll position — would have caught all three anchor-resolution root
   causes immediately, far faster than on-device debugging. A fake
   `SizeCache`/`AnchorResolverDataSource`-style unit test for
   `MasonryPositions` (assert that querying the same two indices in
   different orders, with sizes arriving in different orders, always
   converges to a gap-free, overlap-free layout) would likewise have caught
   both the masonry v1 and v2 bugs immediately.
   `StreamingLayoutWalker` and `StackStreamingLayout` are untested too.
   (`GridPlacement`/`resolveGridTracks` and `FlowStreamingLayout`'s line
   wrapping now have `GridPlacementTests`/`FlowLineBreakTests`, from the
   Grid/variable-Flow session — but nothing yet for `GridStreamingLayout`'s
   own `place`/`proposedSize`, or for `StreamingAnchorPositionState`'s
   geometry-correction specifically on a grid.)
2. **Wire a test plan to a simulator destination** so the existing suite
   (and the new tests above) can actually run, not just compile. Long-standing
   item, never done.
3. **A `scrollTo`/`animateScrollTo` demo screen** — Phase 2's own types have
   never been exercised by any UI. A "jump to item N" control on the lazy
   table (or a new screen) would finally give this a real test surface — and
   would likely immediately expose `animateScrollTo`'s own distance
   resolution inheriting the same per-item-length-summing bug `applyDelta`
   had before this session's fix, on masonry/flow/grid specifically (see the
   anchor-resolution note above's "Still open").
4. **Phase 4's original capstone**: a large (~100k-item) list that loads at
   both ends with inserts on top and must not jump — the actual proof of the
   anchor model's core promise, not yet built.
5. Physical-device verification — everything so far has only been checked on
   the simulator.
6. **`AnchoredGrid`'s fixed mode doesn't support mixed `[GridTrack]` for
   both axes** (only `Int`/`Int`, which is all the calculator needed) — add
   a `columns: [GridTrack], rows: [GridTrack]` initializer if a caller needs
   explicit tracks on both axes at once without scrolling.
