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

Keybindings
-----------

  * `Up` / `Down` / mouse wheel — move the selection between cards.

  * `Home` / `End` — jump to first / last card.

  * `PageUp` / `PageDown` — scroll *within* the selected card. CardList prefers `scroll-content-page-by(Int $direction)` on the card widget if it's available — passing `+1` for PgDown and `-1` for PgUp lets the card decide what one page means relative to its OWN viewport (chat messages have body viewports much smaller than the chat pane itself, and over-scrolling by the chat pane's row count would jump straight past most of the body). Falls back to `scroll-content-by(±self.rows)` for legacy widgets. Cards without either method simply absorb the keypress (no cross-card movement on PgUp/PgDown — Up/Down is the only cross-card movement, by design, so a long scrollable card never surprises the user by jumping to a neighbour). Use it for chat messages, code blocks, log entries — anywhere a single card can outgrow its slot.

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

### has Bool $.bottom-anchor

When True and the rendered cards (from `scroll-top` through the last item) sum to less than the viewport height, render shifts every visible card down so the LAST item ends at the bottom of the viewport rather than leaving empty space below it. Designed for chat-style consumers where new content arrives at the bottom and the user expects the latest message to be anchored there even when the whole conversation fits on screen. Default False — classic top-aligned list rendering for inventory / file-browser / pickers (e.g. AvatarList) where empty space below the last item is the right behaviour.

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

### method scroll-selected-page

```raku
method scroll-selected-page(
    Int $direction
) returns Bool
```

Delegate a one-page scroll to the selected card. Tries `scroll-content-page-by(±1)` first so the card can use its OWN viewport size (a chat message's body is far smaller than the chat pane); falls back to `scroll-content-by(±self.rows)` for legacy cards that only expose the absolute-delta API. Returns True (event handled) whenever a card is selected, even when the card doesn't support either method — the alternative would be falling through to cross-card navigation, which surprises users who expect PgDown to walk further into the current message. Always returning True keeps PgUp/PgDown's contract simple: "scroll inside if you can, otherwise nothing happens".

