NAME
====

Selkie::Widget::RadioGroup - Focusable single-selection list

SYNOPSIS
========

```raku
use Selkie::Widget::RadioGroup;
use Selkie::Sizing;

my $radio = Selkie::Widget::RadioGroup.new(sizing => Sizing.fixed(3));
$radio.set-items(<Small Medium Large>);
$radio.on-change.tap: -> UInt $idx {
    say "Selected: {$radio.selected-label}";
};
```

DESCRIPTION
===========

A vertical list with `(●)`/`( )` indicators showing which option is selected. Cursor navigation (Up/Down) is decoupled from selection — the user can browse without committing. `Enter` or `Space` commits the cursor position as the new selection.

Across `set-items` calls, selection is preserved by label when possible: if the previously-selected label is still in the new list, the selection follows it to its new index. Falls back to index clamp otherwise.

Includes a scrollbar on the right edge if the item count exceeds the viewport height.

EXAMPLES
========

Sync with store state
---------------------

```raku
$app.store.subscribe-with-callback(
    'sync-density',
    -> $s { ($s.get-in('settings', 'density') // 0).Int },
    -> Int $v { $radio.select-index($v) },  # no-op if unchanged — safe
    $radio,
);
$radio.on-change.tap: -> $v {
    $app.store.dispatch('settings/set', field => 'density', value => $v);
};
```

SEE ALSO
========

  * [Selkie::Widget::Select](Selkie--Widget--Select.md) — compact dropdown equivalent

  * [Selkie::Widget::Checkbox](Selkie--Widget--Checkbox.md) — boolean toggle

  * [Selkie::Widget::ListView](Selkie--Widget--ListView.md) — similar UI but for navigation, not selection

### method items

```raku
method items() returns List
```

The current option labels as a List.

### method cursor

```raku
method cursor() returns UInt
```

Index of the cursor (the row Up / Down has navigated to). The cursor and the selection are tracked separately — moving the cursor with arrow keys does not change the selection until the user presses Enter or Space.

### method selected

```raku
method selected() returns UInt
```

Index of the currently-selected option. Stable across cursor movement; only changes on commit (Enter / Space / mouse click).

### method selected-label

```raku
method selected-label() returns Str
```

Label of the currently-selected option, or the `Str` type object if there are no items.

### method on-change

```raku
method on-change() returns Supply
```

Supply that emits the new selected index whenever the selection changes. Does not fire on cursor-only movement.

### method set-items

```raku
method set-items(
    @new-items
) returns Mu
```

Replace the option labels. Preserves the current selection by label if it's still present in the new list (so a re-build of the same options doesn't snap selection back to 0); otherwise clamps to the new bounds. Does **not** emit on `on-change` — the selection is considered unchanged from the user's perspective when the same label is still selected. Mark-dirties only.

### method select-index

```raku
method select-index(
    Int $idx where { ... }
) returns Mu
```

Commit a new selection. `$idx` is clamped to the last item; the cursor jumps to match. Emits on `on-change` only when the selection actually changed (idempotent on no-ops). No-op when the list is empty.

