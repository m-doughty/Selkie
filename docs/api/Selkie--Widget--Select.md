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

### method select-by-value

```raku
method select-by-value(
    Str:D $value
) returns Mu
```

Programmatically select the entry matching `$value` (string equality on the items list). No-op when the value isn't present or when it's already selected, so callers don't have to guard against absent items themselves. Fires `on-change` only when the selection actually moves.

