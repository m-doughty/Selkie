NAME
====

Selkie::Widget::ViewportedCardList - Row-scrolled selectable list of card widgets

SYNOPSIS
========

```raku
use Selkie::Widget::ViewportedCardList;
use Selkie::Sizing;

# Standard chat-history pane: latest message anchored to the bottom
# of the viewport with empty space above when content is shorter
# than the pane, and auto-scroll-to-bottom while a streaming
# message grows.
my $chat = Selkie::Widget::ViewportedCardList.new(
    sizing        => Sizing.flex,
    bottom-anchor => True,
    follow-bottom => True,
);

$chat.add-item(
    $message,
    root   => $message.root,
    height => $message-height,
    border => $message.border,
);

# Streaming token arrived — last card grew. The viewport tracks the
# new bottom automatically as long as the user hasn't scrolled
# upward; if they have, the new content piles up below their parked
# position until they scroll back to the bottom.
$chat.set-item-height($chat.count - 1, $new-height);
```

DESCRIPTION
===========

Like [Selkie::Widget::CardList](Selkie--Widget--CardList.md), each item is an arbitrary widget with a logical height and optional focus border. Unlike CardList, scrolling is by content row: a viewport can start in the middle of any card.

`bottom-anchor` aligns the last item to the bottom of the viewport when total content is shorter than the pane (chat-history semantics — short transcripts hug the input row, long ones scroll). `follow- bottom` keeps the bottom row visible as content grows or new cards are added (streaming text, log tails). The follow latch is maintained exclusively by user-driven scroll calls; mid-frame content-shape changes (`set-item-height` from a streaming token, `add-item` for a new message) clamp without disturbing it, so a growing or appended message stays visible without yanking the viewport away from a user who has scrolled up to read history.

### sub viewported-cardlist-shim-available

```raku
sub viewported-cardlist-shim-available(
    Bool $val?
) returns Mu
```

Module-level latch tracking whether `libnotcurses_native_shim`'s `notcurses_native_copy_cells` is callable in this process. Optimistic at start; flipped to False the first time the shim binding throws (typically "Cannot locate native library" on installs where the shim wasn't compiled — see Notcurses::Native's Build.rakumod for when that can happen). Once flipped, every instance uses the Raku per-cell fallback for the rest of the process — re-trying would just re-throw and be slower than the fallback. Test/benchmark hook to inspect or override the shim latch. Pass no argument to read; pass True/False to force the path used by subsequent `!copy-cells` calls. Used by xt/ tests to drive both code paths against the same widget tree without needing two separate processes. NOT part of the public API — don't depend on this from app code; the binding's own load- failure detection is the right hook for runtime decisions.

### has Bool $.bottom-anchor

Anchor the last item to the bottom of the viewport when total content is shorter than the pane. Empty space appears above the cards instead of below — standard chat-history layout where the transcript reads upward from the input. With `bottom-anchor =` False> (default) short content top-aligns.

### has Bool $.follow-bottom

Auto-pin the bottom of content as it grows. When True, each render checks the `follow-active` latch; if set, the new scroll offset snaps to `max-offset` so streaming additions and height growth on the last card stay visible. The latch is maintained exclusively by `scroll-to` (the funnel for every user-driven scroll mutator), so content-shape changes between frames don't disturb follow status. Any user scroll up disengages until they scroll back to the bottom.

### has Bool $!follow-active

Persistent tail-follow latch, only meaningful when `follow-bottom` is True. Computed on every `scroll-to` call based on whether the user landed at `max-offset`. `render` reads this flag without touching it; mid-frame content-shape changes (`set-item-height` while a streamed message grows, `add-item` appending a new card) do not affect follow status. The previous implementation re-derived follow per frame from `scroll-offset `= max-offset> against the freshly-grown max-offset. That snapshot proved fragile: the very first streamed token grew `content-height` past the cached `scroll-offset`, the per-frame check flipped to False, and `follow-bottom` silently disengaged on token #1. Tracking persistent state survives.

### has Bool $!layout-dirty

Layout-vs-content dirty distinction. Layout-dirty means card positions in `self.plane` have shifted: scroll moved, a card's height changed, items were added or removed, the viewport resized. The whole visible region needs a full erase + full re-merge. Content-only dirty (this flag is False, but VCL's own `is-dirty` latch is True via the parent-chain cascade from a descendant's `mark-dirty`) means a card's contents changed at stable cell positions — typically an `image-gen/progress` bar update or a streaming text token that fits within the existing wrapped row count. Only that card's region needs erasing and re-merging; other visible cards' cells in `self.plane` are still valid from the previous frame. Default True so the first render does the full path. Cleared at the end of every render. Set by `scroll-to` (when offset changes), `set-item-height` (when height changes), `add- item`, `clear-items`, `handle-resize`.

### method follow-active

```raku
method follow-active() returns Bool
```

Read-only view of the persistent tail-follow latch. True when `follow-bottom` is enabled and the user is at (or has been clamped to) `max-offset`. Always True when `follow-bottom` is False — the flag is simply unused. Useful for surfacing a "follow-mode" indicator in the UI and for tests that want to verify follow transitions without driving a full render.

### method set-item-height

```raku
method set-item-height(
    Int $idx,
    Int $height
) returns Mu
```

Update the cached row height of the card at `$idx` and clamp the current scroll offset to the new `max-offset`. Does NOT route through `scroll-to`: that's the user-input funnel that recomputes `$!follow-active` from where the caller landed, and a content-shape change is not a user action. Routing through it would clobber the latch the moment the last card grew (old offset is no longer >= new max), defeating `follow-bottom` on the very first streamed token. The render pass re-engages the latch separately if a content shrink leaves the offset exactly at the new max — see `render`. Skips entirely (no clamp, no mark-dirty, no layout-dirty) when the new height equals the cached one. Streaming consumers call this on every token via `self!card-height($content, $role)`; most tokens append to an existing wrapped line and don't grow the card's row count, so the call is a true no-op. Forcing a re-render in that case used to trigger a full ViewportedCardList re-merge per token.

### method scroll-to

```raku
method scroll-to(
    Int $row where { ... }
) returns Mu
```

Set the scroll offset to `$row` (clamped to `max-offset`). All user-driven scroll mutators — `scroll-by`, `scroll-page-by`, `scroll-to-start`, `scroll-to-end`, the mouse-wheel handler, key navigation, and `!ensure-selected-visible` — funnel through here so the `follow-active` latch updates in exactly one place: re-engaged at `max-offset`, disengaged anywhere short of it. Content-shape changes (`set-item-height`, `add-item`) intentionally do not route through here; they clamp directly without disturbing the latch.

### method render

```raku
method render() returns Mu
```

Two-phase render. Phase 1 walks visible items, positions and sizes their planes inside the backing plane, and renders each card whose subtree changed since the previous frame (or every card if `$!layout-dirty` — scroll, height, add/remove). Phase 2 merges the rendered card planes onto `self.plane`: =item * Layout-dirty path: erase `self.plane` once and re-merge every visible card. Card positions in `self.plane` have shifted, so cells from the previous frame are stale everywhere. =item * Content-dirty-only path: leave `self.plane` alone except for the dirty cards' regions. Erase each dirty card's slice via `ncplane_erase_region`, then merge that card. Other cards' cells are still in the right place from last frame and survive untouched. This is the hot path during ComfyUI image-gen progress and during streaming text tokens that don't grow the wrap row count. The merge primitive itself is `!copy-cells` — see that method's notes on why the obvious-looking `ncplane_mergedown` swap is wrong here (mergedown composites at absolute pile coordinates, not at the scroll-translated dst we need). The layout/content split above is what saves work in the common streaming + progress cases.

### method copy-cells

```raku
method copy-cells(
    Notcurses::Native::Types::NcplaneHandle $src,
    Int :$src-y!,
    Int :$src-x!,
    Int :$dst-y!,
    Int :$dst-x!,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Mu
```

One-call batched copy of a `$rows × $cols` rectangle from `$src` at (src-y, src-x) onto `self.plane` at (dst-y, dst-x). Substitutes the source plane's base cell into empty cells so Border interiors carry the theme background through the copy (matches notcurses's own `ncplane_at_yx` behaviour). Fast path: `libnotcurses_native_shim`'s `notcurses_native_copy_cells` — one C call per invocation instead of 5+ NativeCall trips per cell. For a typical 30×100 widget plane that's a 15,000× reduction in boundary crossings. Fallback path (`!copy-cells-raku`): the original per-cell Raku loop, used when the shim isn't loadable (no C toolchain AND no prebuilt-bundled shim — see Notcurses::Native's Build.rakumod). Functionally identical, just slower; the latch flips once per process so we don't retry on every render. Other primitives considered and rejected: =item `ncplane_mergedown` — composites at absolute pile coordinates (validates the slice args but doesn't actually use them; see `src/lib/render.c` in notcurses), not at the scroll-translated dst we need. Cards' planes live at backing-plane positions, so mergedown paints them there. Wrong for our usage. =item `ncplane_contents` — bulk-reads cell glyphs but discards styles/colors. Lossy.

### method copy-cells-raku

```raku
method copy-cells-raku(
    Notcurses::Native::Types::NcplaneHandle $src,
    Int :$src-y!,
    Int :$src-x!,
    Int :$dst-y!,
    Int :$dst-x!,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Mu
```

Per-cell Raku fallback for !copy-cells. Used only when the notcurses native shim isn't loadable. Reads each source cell via `ncplane_at_yx_cell` (the heap-stable variant of `ncplane_at_yx` — see `memory/nativecall_str_free_trap.md` for why we don't use the malloc'ing version), substitutes the source plane's base cell when a cell has an empty glyph (the Border-interior case), and writes each cell to `self.plane` via `ncplane_putstr_yx` with matched styles + channels.

