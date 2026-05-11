NAME
====

Selkie::Widget::Select - Compact dropdown picker

SYNOPSIS
========

```raku
use Selkie::Widget::Select;
use Selkie::Sizing;

my $select = Selkie::Widget::Select.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Choose a model',
    max-visible => 8,
);
$select.set-items(<gpt-4 claude-opus local-model>);
$select.on-change.tap: -> UInt $idx {
    say $select.selected-value;
};
```

DESCRIPTION
===========

A single-line control showing the currently selected value with a `▼` marker. `Enter` or `Space` opens a dropdown list as a child plane rendered on top of the surrounding layout. Esc cancels; Enter commits the highlighted option.

While open, the Select acts as a local focus trap — arrow keys and Enter navigate the dropdown, not the surrounding app. Losing focus auto-closes the dropdown.

Use `RadioGroup` instead when you want the options always visible; use `Select` when you want compact real estate.

EXAMPLES
========

Inside a form
-------------

```raku
my $theme-select = Selkie::Widget::Select.new(
    sizing => Sizing.fixed(1),
);
$theme-select.set-items(<Auto Light Dark>);

$app.store.subscribe-with-callback(
    'sync-theme-select',
    -> $s { ($s.get-in('settings', 'theme') // 0).Int },
    -> Int $v { $theme-select.select-index($v) },
    $theme-select,
);
$theme-select.on-change.tap: -> $v {
    $app.store.dispatch('settings/set', field => 'theme', value => $v);
};
```

SEE ALSO
========

  * [Selkie::Widget::RadioGroup](Selkie--Widget--RadioGroup.md) — always-visible equivalent

  * [Selkie::Widget::ListView](Selkie--Widget--ListView.md) — full-height scrollable list

### method claims-overlay-at

```raku
method claims-overlay-at(
    Int $y,
    Int $x
) returns Bool
```

When the dropdown is open, claim overlay rights for the dropdown rows. The framework's `widget-at-in` does an overlay pass against the entire tree before normal containment walk, so clicks on the dropdown reach the Select even though the parent layout's bounds end at our closed-display row. The closed-display row itself stays under standard contains-point — when the dropdown isn't open, we behave like any other 1-row widget.

### method items

```raku
method items() returns List
```

The current option labels as a List.

### method selected

```raku
method selected() returns UInt
```

Index of the committed selection.

### method selected-value

```raku
method selected-value() returns Str
```

Label of the committed selection, or the `Str` type object when no items are set.

### method is-open

```raku
method is-open() returns Bool
```

Whether the dropdown is currently open.

### method on-change

```raku
method on-change() returns Supply
```

Supply that emits the new selected index whenever the selection changes (Enter / Space / mouse pick / `select-index` / `select-by-value`). Cursor-only movement inside the open dropdown does not emit until the user commits.

### method set-items

```raku
method set-items(
    @new-items
) returns Mu
```

Replace the option labels. Preserves the current selection by label if it's still present in the new list (so a re-build of the same options doesn't snap selection back to 0); otherwise clamps to the new bounds. Closes the dropdown if it was open. Mark-dirties only — does not emit on `on-change`.

### method select-index

```raku
method select-index(
    Int $idx where { ... }
) returns Mu
```

Commit the option at `$idx` as the new selection (clamped to the last item). Emits on `on-change` only when the selection actually changes (idempotent on no-ops). No-op when the list is empty.

### method select-by-value

```raku
method select-by-value(
    Str:D $value
) returns Mu
```

Programmatically select the entry matching `$value` (string equality on the items list). No-op when the value isn't present or when it's already selected, so callers don't have to guard against absent items themselves. Fires `on-change` only when the selection actually moves.

### method set-focused

```raku
method set-focused(
    Bool $f
) returns Mu
```

Set the input's focus state. Losing focus auto-closes any open dropdown — Select is a local focus trap while open, so leaving focus shouldn't strand the dropdown on screen.

### method is-focused

```raku
method is-focused() returns Bool
```

Whether the widget currently has focus.

### method open

```raku
method open() returns Mu
```

Open the dropdown. No-op when already open or when there are no items. Resets the dropdown cursor to the committed selection so the highlight starts there. Does not emit on `on-change`.

### method close

```raku
method close() returns Mu
```

Close the dropdown without committing the cursor. Used by Esc and by `set-focused(False)`; programmatic callers that want to commit should call `select-index` first.

### method destroy

```raku
method destroy() returns Mu
```

Tear down the dropdown plane and the widget's own plane. Called on app shutdown.

