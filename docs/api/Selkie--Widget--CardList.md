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

  * `:min-display-height` — smallest `display-h` at which a partial render of this card is still meaningful. Non-selected cards whose visible height would fall below this threshold are parked rather than rendered as a sliver. Defaults to `1` (any positive sliver renders, the pre-existing behaviour). Useful for cards with structural minimums — e.g. a chat card with a fixed-height avatar plus a name row plus a border edge needs at least `avatar-rows + 2` rows before its partial render reads as "the bottom of a message" instead of "merged into the neighbour". The selected card is always exempt from this check; if it can't fully fit, the list relies on its own internal scrolling (e.g. a wrapped `ScrollView`) to handle the overflow.

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

### method on-select

```raku
method on-select() returns Supply
```

Supply that emits the new selected index whenever the selection moves (Up / Down / mouse click / `select-index` / `select-first` / `select-last`). Does **not** fire on `add-item` or `clear-items` — those only mark-dirty.

### method selected

```raku
method selected() returns Int
```

Index of the selected card. Stable across resizes / rebuilds. Returns 0 when the list is empty (selection is conventionally at index 0 for empty lists; pair with `count` if you need to disambiguate).

### method count

```raku
method count() returns Int
```

Number of cards in the list.

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

### method selected-item

```raku
method selected-item() returns Mu
```

The inner widget of the selected card (the `$widget` argument passed to `add-item`), or `Nil` when the list is empty / index is out of range.

### method children

```raku
method children() returns List
```

Expose each card's root (and its border, if any) as `children` so Container-level cascade helpers (notably `!unsubscribe-tree`) reach them. CardList stores its cards in `@!items` rather than the inherited `@!children` array, so without this override the cascade walks an empty list and leaks subscriptions anchored inside cards.

### method add-item

```raku
method add-item(
    $widget,
    :$root!,
    :$height!,
    :$border,
    Int :$min-display-height where { ... } = 1
) returns Mu
```

Append a card. The four parameters describe the card's structure: #| #| `$widget` — the inner widget the card represents. Returned by #| `selected-item`. Usually a `RichText`, `Text`, or custom widget; #| does not need to manage its own plane (the `:root` handles that). #| #| `:root!` — the widget that gets a plane and is rendered. Often a #| `Border` wrapping the inner widget, or the inner widget itself if #| no border is wanted. CardList drives reposition / resize / park on #| this root each frame. #| #| `:height!` — the card's logical height in cells. CardList uses #| this to lay out cards stacked top-to-bottom and decide which fit #| in the viewport. Variable-height cards are the whole point — every #| card can have its own height. #| #| `:border` — optional. When provided, CardList drives this widget's #| `set-has-focus` per render so the border highlights the selected #| card regardless of where keyboard focus actually lives. Pass the #| same Border instance you used as `:root` to wire the highlight. #| #| `:min-display-height` — when a card is partially clipped at the #| top or bottom edge of the viewport, this is the minimum visible #| height before CardList parks the card entirely instead of showing #| a sliver. Default 1.

### method clear-items

```raku
method clear-items() returns Mu
```

Destroy every card and reset selection / scroll. Calls `destroy` on each card's root, so any subscriptions or sprixels owned by cards are cleaned up. Use before rebuilding the list to avoid leaks; for incremental updates, prefer `set-item-height` + selective `add-item`.

### method set-item-height

```raku
method set-item-height(
    Int $idx,
    Int $height
) returns Mu
```

Update an existing card's logical height (e.g. when its content reflows after a viewport resize). No-op when `$idx` is out of range. Triggers re-layout on the next render.

### method select-index

```raku
method select-index(
    Int $idx
) returns Mu
```

Move the selection to `$idx` (clamped to the valid range). Emits on `on-select`. No-op when the list is empty.

### method select-last

```raku
method select-last() returns Mu
```

Jump selection to the last card. Useful after appending content in chat-style consumers where the user wants to track the latest message. Does **not** emit on `on-select` — symmetry with `select-first`.

### method select-first

```raku
method select-first() returns Mu
```

Jump selection to the first card. Does **not** emit on `on-select`.

### method scroll-up

```raku
method scroll-up() returns Mu
```

Move selection one card up. Alias for the internal `!select-prev` so external callers can advance the cursor without registering a keybind.

### method scroll-down

```raku
method scroll-down() returns Mu
```

Move selection one card down. See `scroll-up`.

### method scroll-selected-page

```raku
method scroll-selected-page(
    Int $direction
) returns Bool
```

Delegate a one-page scroll to the selected card. Tries `scroll-content-page-by(±1)` first so the card can use its OWN viewport size (a chat message's body is far smaller than the chat pane); falls back to `scroll-content-by(±self.rows)` for legacy cards that only expose the absolute-delta API. Returns True (event handled) whenever a card is selected, even when the card doesn't support either method — the alternative would be falling through to cross-card navigation, which surprises users who expect PgDown to walk further into the current message. Always returning True keeps PgUp/PgDown's contract simple: "scroll inside if you can, otherwise nothing happens".

