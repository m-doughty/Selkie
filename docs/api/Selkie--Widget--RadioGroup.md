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

