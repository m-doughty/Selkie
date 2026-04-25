NAME
====

Selkie::Widget::CardList - Cursor-navigated scrollable list of variable-height widgets

SYNOPSIS
========

```raku
use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::RichText;
use Selkie::Sizing;

my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

# Each card has: an inner widget, a root (often a Border wrapping the
# inner widget), a height, and an optional border for focus highlighting.
for @messages -> %msg {
    my $rich = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $rich.set-content(%msg<spans>);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($rich);
    $cards.add-item($rich, root => $border, height => 3, :$border);
}

$cards.on-select.tap: -> UInt $idx { show-detail($cards.selected-item) };
```

DESCRIPTION
===========

Like [Selkie::Widget::ListView](Selkie--Widget--ListView.md), but each item is an arbitrary widget of configurable height rather than a string. The cursor moves between cards; the selected card always fully fits in the viewport, and the card at the opposite end may be partially clipped (with a visual truncation hint if the card's widget supports `set-clipped`).

Use this when your items are structured: chat messages with avatars, tasks with metadata, email threads, etc. Use `ListView` if items are just strings.

Item shape
----------

Each item is registered with:

  * `$widget` (positional) — the renderable widget inside the card (what the user sees)

  * `:root` — the outermost container for the card (usually a Border wrapping the inner widget)

  * `:height` — the card's logical height in rows

  * `:border` — optional Border for focus-highlight integration

EXAMPLES
========

Chat messages
-------------

See `examples/chat.raku` for the full version. In brief:

```raku
$app.store.subscribe-with-callback(
    'chat-cards',
    -> $s { $s.get-in('messages') // [] },
    -> @msgs {
        $cards.clear-items;
        for @msgs -> %m { $cards.add-item(|build-card(%m)) }
        $cards.select-last;
    },
    $cards,
);
```

SEE ALSO
========

  * [Selkie::Widget::ListView](Selkie--Widget--ListView.md) — simpler, string-only version

  * [Selkie::Widget::ScrollView](Selkie--Widget--ScrollView.md) — non-interactive virtual scroll

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Resize own plane only. Cards are sized / positioned / parked in `render` based on the current viewport — a single authoritative pass per frame. Cascading handle-resize here with each card's stored logical height had produced the "two-state plane" bug where cards briefly had logical-height planes that extended past CardList's new bounds, bleeding into whatever widget sits below.

### method park

```raku
method park() returns Mu
```

Park self plus every card root. CardList stores its items in `@!items` rather than `self.children`, so the standard Container.park doesn't reach them; we recurse explicitly here. Without this override, when a CardList scrolls or its host screen is swapped out, sprixels carried by Image widgets inside cards keep painting on the terminal at their last screen position.

### method children

```raku
method children() returns List
```

Expose each card's root (and its border, if any) as `children` so Container-level cascade helpers (notably `!unsubscribe-tree`) reach them. CardList stores its cards in `@!items` rather than the inherited `@!children` array, so without this override the cascade walks an empty list and leaks subscriptions anchored inside cards.

