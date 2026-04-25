NAME
====

Selkie::Widget::Border - Decorative frame around a single content widget

SYNOPSIS
========

```raku
use Selkie::Widget::Border;
use Selkie::Sizing;

my $border = Selkie::Widget::Border.new(
    title  => 'Characters',
    sizing => Sizing.fixed(20),
);
$border.set-content($avatar-list);
```

DESCRIPTION
===========

Draws a box around a single child widget. Auto-highlights when any descendant has focus (via a store subscription on `ui.focused-widget` — it's the canonical example of the "widget reacts to store state" pattern).

Requires at least 3x3 dimensions. Redraws its edges after content renders to cover pixel bleed from image blits — useful when wrapping an Image.

Opting out of store-driven focus
--------------------------------

Set `focus-from-store = False` to disable both the store subscription and the render-time override. In that mode `set-has-focus` is the only writer and its value persists across renders. Intended for Borders managed by a parent container with richer selection semantics than "focused descendant" — `CardList`, for example, which wants its *selected* card's Border highlighted regardless of whether keyboard focus has moved elsewhere.

Swapping content
----------------

By default, `set-content` destroys the outgoing widget. Pass `:!destroy` to swap while keeping the old widget alive — useful for tab-style panes that cycle through persistent views:

```raku
$border.set-content($view-a);
$border.set-content($view-b, :!destroy);    # $view-a survives
$border.set-content($view-a, :!destroy);    # swap back, still intact
```

EXAMPLES
========

Named panels
------------

```raku
my $left = Selkie::Widget::Border.new(
    title  => 'Characters',
    sizing => Sizing.fixed(20),
);
$left.set-content($char-list);

my $right = Selkie::Widget::Border.new(
    title  => 'Chat',
    sizing => Sizing.flex,
);
$right.set-content($chat-view);
```

Stacking borders
----------------

Use `hide-top-border` / `hide-bottom-border` to share edges between adjacent panels:

```raku
$top-panel.hide-bottom-border    = True;
$bottom-panel.hide-top-border    = True;
```

SEE ALSO
========

  * [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — centered overlay; also has `set-content(:!destroy)`

  * [Selkie::Theme](Selkie--Theme.md) — `border` / `border-focused` slots control appearance

### has Bool $.focus-from-store

When True (default), the Border subscribes to `ui.focused-widget` and its `render` re-derives `$!has-focus` from the store on every frame — the normal "highlight when any descendant is focused" pattern. When False, the Border treats `set-has-focus` as the single source of truth: no subscription, no render-time override. This is the right mode for Borders whose focus state is managed by a parent container that has richer selection semantics than "focused descendant" — `CardList` being the canonical case, where the *selected* card's border should stay highlighted regardless of whether keyboard focus has moved out to another widget.

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Resize own plane. Content is sized inside `render` (after the inner-top / inner-rows / inner-cols computation that accounts for hide-top/bottom-border). No cascade here — one layout pass per frame, top-down via render.

