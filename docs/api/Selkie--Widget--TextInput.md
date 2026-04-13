NAME
====

Selkie::Widget::TextInput - Single-line text input with cursor and editing

SYNOPSIS
========

```raku
use Selkie::Widget::TextInput;
use Selkie::Sizing;

my $input = Selkie::Widget::TextInput.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Search...',
);

$input.on-submit.tap: -> $text { run-search($text) };
$input.on-change.tap: -> $text { update-preview($text) };

# Password field: mask characters
my $pw = Selkie::Widget::TextInput.new(
    sizing    => Sizing.fixed(1),
    mask-char => '•',
);
```

DESCRIPTION
===========

A one-line text input. Arrow keys, Home, End, Backspace, and Delete behave as you'd expect. Characters wider than the visible width horizontally scroll the view to follow the cursor.

Two Supplies:

  * `on-submit` — fires once when the user presses Enter, carrying the current text

  * `on-change` — fires on every keystroke that modifies the buffer

For programmatic updates that shouldn't re-dispatch (e.g. syncing from a store subscription), use `set-text-silent` — it updates the buffer without emitting on `on-change`.

Modified keys (Ctrl, Alt, Super) bubble past the input so global keybinds still work. Bare characters are consumed for typing.

EXAMPLES
========

Store-synced input
------------------

```raku
$app.store.subscribe-with-callback(
    'sync-name',
    -> $s { ($s.get-in('form', 'name') // '').Str },
    -> $v { $name-input.set-text-silent($v) if $name-input.text ne $v },
    $name-input,
);
$name-input.on-change.tap: -> $v {
    $app.store.dispatch('form/set', field => 'name', value => $v);
};
```

SEE ALSO
========

  * [Selkie::Widget::MultiLineInput](Selkie--Widget--MultiLineInput.md) — multi-line variant with word wrap

  * [Selkie::Widget::Button](Selkie--Widget--Button.md) — for commit-only actions

