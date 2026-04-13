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

