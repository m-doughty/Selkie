NAME
====

Selkie::Widget::ListView - Scrollable single-select list of strings

SYNOPSIS
========

```raku
use Selkie::Widget::ListView;
use Selkie::Sizing;

my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
$list.set-items(<Alpha Beta Gamma Delta>);

$list.on-select.tap:   -> $name { say "cursor on: $name" };
$list.on-activate.tap: -> $name { say "selected: $name" };
$list.on-key('d', -> $ { delete-item });
```

DESCRIPTION
===========

A vertical list of string entries with a cursor. Arrow keys (and PageUp/PageDown/Home/End/mouse wheel) move the cursor; `Enter` activates. The selected item is always fully visible; the list auto-scrolls as the cursor moves.

Two Supplies:

  * `on-select` — fires whenever the cursor moves. Use for "show details of highlighted"

  * `on-activate` — fires when the user presses Enter. Use for "open this item"

Across `set-items` calls, cursor position is preserved by label when possible. If the previously-selected string is still in the new list, the cursor follows it. Otherwise the cursor index is clamped to bounds. Only resets to 0 when the list becomes empty.

Includes a scrollbar on the right edge when items exceed the viewport.

EXAMPLES
========

Store-driven list
-----------------

```raku
$app.store.subscribe-with-callback(
    'file-list',
    -> $s { ($s.get-in('files') // []).map(*<name>).List },
    -> @items { $list.set-items(@items) },     # cursor preserved by value
    $list,
);

$list.on-activate.tap: -> $name {
    $app.store.dispatch('files/open', :$name);
};
```

SEE ALSO
========

  * [Selkie::Widget::CardList](Selkie--Widget--CardList.md) — same pattern for variable-height cards

  * [Selkie::Widget::RadioGroup](Selkie--Widget--RadioGroup.md) — similar UI but for one-of-many selection

### method items

```raku
method items() returns List
```

The current items as a List.

### method cursor

```raku
method cursor() returns UInt
```

Index of the cursor (the highlighted row). Always 0 when the list is empty.

### method selected

```raku
method selected() returns Str
```

The string at the cursor, or the `Str` type object when empty.

### method on-select

```raku
method on-select() returns Supply
```

Supply that emits the selected string whenever the cursor moves (Up / Down / mouse click / `select-index`). Fires once on `set-items` if the new list is non-empty.

### method on-activate

```raku
method on-activate() returns Supply
```

Supply that emits the selected string when the user activates a row (Enter, Space, double-click). `on-select` fires for cursor movement; `on-activate` only fires for explicit activation.

### method set-items

```raku
method set-items(
    @new-items
) returns Mu
```

Replace the items. The cursor tracks the previously-selected string if it's still present in the new list (so a list refresh doesn't jump the user back to row 0); otherwise clamps to the new bounds. Emits on `on-select` when the resulting list is non-empty.

### method select-index

```raku
method select-index(
    Int $idx where { ... }
) returns Mu
```

Move the cursor to `$idx` (clamped to the last item) and emit on `on-select`. No-op when the list is empty.

