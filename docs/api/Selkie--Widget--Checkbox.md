NAME
====

Selkie::Widget::Checkbox - Focusable boolean toggle

SYNOPSIS
========

```raku
use Selkie::Widget::Checkbox;
use Selkie::Sizing;

my $cb = Selkie::Widget::Checkbox.new(
    label  => 'Enable notifications',
    sizing => Sizing.fixed(1),
);
$cb.on-change.tap: -> Bool $checked {
    $app.store.dispatch('settings/notifications', value => $checked);
};
```

DESCRIPTION
===========

Renders as `[x] label` when checked, `[ ] label` when unchecked. Space or Enter toggles the state.

`set-checked` is idempotent — passing the current value is a no-op and doesn't emit on `on-change`. Safe to call from a store subscription without causing feedback loops.

EXAMPLES
========

Syncing with the store
----------------------

```raku
# Subscribe: reflect store changes into the widget
$app.store.subscribe-with-callback(
    'sync-notif',
    -> $s { $s.get-in('settings', 'notifications') // True },
    -> Bool $v { $cb.set-checked($v) },   # no-op if unchanged — safe
    $cb,
);

# Emit: user toggle dispatches to the store
$cb.on-change.tap: -> Bool $v {
    $app.store.dispatch('settings/set', field => 'notifications', value => $v);
};
```

SEE ALSO
========

  * [Selkie::Widget::RadioGroup](Selkie--Widget--RadioGroup.md) — one-of-many selection

  * [Selkie::Widget::Button](Selkie--Widget--Button.md) — plain action button

### has Str $.label

The label displayed after the `[x]` / `[ ]` indicator. Required.

### method checked

```raku
method checked() returns Bool
```

Current state.

### method set-checked

```raku
method set-checked(
    Bool:D $v
) returns Mu
```

Set the state, emitting on-change only if the value actually changed. No-op on same-value assignments — safe to call from a store subscription.

### method toggle

```raku
method toggle() returns Mu
```

Flip the state and emit on-change unconditionally.

### method on-change

```raku
method on-change() returns Supply
```

Supply emitting `Bool` each time the state changes.

