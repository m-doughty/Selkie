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

