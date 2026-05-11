NAME
====

Selkie::EffectiveBounds - The on-screen rectangle a widget may safely paint into

SYNOPSIS
========

```raku
use Selkie::EffectiveBounds;

# Compute via Widget.effective-bounds — apps don't usually construct
# these directly:
my $eb = $some-widget.effective-bounds;

if $eb.is-empty {
    # Widget is entirely outside the visible region — don't paint
} else {
    # The visible rectangle is at ($eb.abs-y, $eb.abs-x), sized
    # $eb.rows by $eb.cols. The widget's own plane has $eb.clip-top
    # rows chopped off the top and $eb.clip-left cols off the left.
}
```

DESCRIPTION
===========

Notcurses does **not** clip a child plane's painted content to its parent plane's bounds. A child plane sized larger than its parent paints past the parent's edge into siblings or grandparents. Pixel sprixels (the protocol-agnostic name covering Sixel, Kitty graphics, and iTerm2 inline images) are even worse — they paint at absolute terminal pixel coordinates regardless of any plane hierarchy.

`Selkie::EffectiveBounds` is the value class returned by [Selkie::Widget](Selkie--Widget.md)'s `effective-bounds` method, which walks the parent chain and computes the rectangular intersection of the widget's plane with every ancestor's plane and the terminal viewport. The result is the on-screen rectangle into which the widget may safely paint pixels — anything outside this rectangle would bleed past an ancestor's visible region.

[Selkie::Widget::Image](Selkie--Widget--Image.md) uses this to size its blit-plane to the visible intersection, ensuring sprixel pixels never overflow into territory occupied by other widgets. Custom widgets that allocate their own blit plane (following the [Selkie::Widget::Image](Selkie--Widget--Image.md) pattern) should do the same.

The clip-top / clip-left fields
-------------------------------

When a widget is partially clipped on its top or left edge (typical for a CardList card scrolled past the top of the viewport, or a horizontal scroll), the visible rectangle's top-left does not coincide with the widget's plane's top-left. `clip-top` and `clip-left` tell the renderer how many rows / columns of its own plane fall outside the visible region at the leading edges, so a sub-plane (like an Image's blit-plane) can be positioned to land inside the visible intersection rather than at the widget's own (0, 0).

SEE ALSO
========

  * [Selkie::Widget](Selkie--Widget.md) — owns `effective-bounds` and `clip-to-ancestors`

  * [Selkie::Widget::Image](Selkie--Widget--Image.md) — sizes its blit-plane to these bounds and drives the surrounding sprixel destroy / re-blit lifecycle

### has Int $.abs-y

Top edge of the visible intersection in absolute screen coordinates.

### has Int $.abs-x

Left edge of the visible intersection in absolute screen coordinates.

### has UInt $.rows

Height of the visible intersection in cells. Zero when the widget is entirely outside its ancestors or the terminal.

### has UInt $.cols

Width of the visible intersection in cells. Zero when the widget is entirely outside its ancestors or the terminal.

### has UInt $.clip-top

Number of rows of the widget's own plane that fall above the visible intersection (chopped off the top by an ancestor's edge).

### has UInt $.clip-left

Number of columns of the widget's own plane that fall left of the visible intersection (chopped off the left by an ancestor's edge).

### method is-empty

```raku
method is-empty() returns Bool
```

True when the widget has no on-screen visible area — entirely outside an ancestor or the terminal viewport. Renderers should early-return on `is-empty` rather than emit any pixels.

### sub intersect-rect

```raku
sub intersect-rect(
    Int :$ay!,
    Int :$ax!,
    Int :$ah! where { ... },
    Int :$aw! where { ... },
    Int :$by!,
    Int :$bx!,
    Int :$bh! where { ... },
    Int :$bw! where { ... },
    Int :$clip-top where { ... } = 0,
    Int :$clip-left where { ... } = 0
) returns Selkie::EffectiveBounds
```

Compute the rectangular intersection of two cell rectangles given as `(abs-y, abs-x, rows, cols)` tuples. Returns a new `Selkie::EffectiveBounds` with `clip-top` and `clip-left` reflecting how much of the first rectangle was chopped off its leading edges. `is-empty` when the rectangles don't overlap.

### sub set-terminal-viewport-provider

```raku
sub set-terminal-viewport-provider(
    &p
) returns Nil
```

Set the terminal viewport provider — a closure returning `(rows, cols)` for the active terminal. `Selkie::App` calls this on init so `Selkie::Widget.effective-bounds` can intersect every widget against the terminal's visible area. Tests can pass a fixed-size closure to simulate a small terminal; pass `{ (1_000, 1_000) }` to reset to the generous default.

### sub terminal-viewport

```raku
sub terminal-viewport() returns List
```

Current terminal viewport dimensions as `(rows, cols)`, queried through the provider closure (set by [Selkie::App](Selkie--App.md) at init).

