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

Modified keys (Ctrl, Alt, Super) bubble past the input so global keybinds still work — except when the OS keyboard layout has already composed the modifier into a different printable character (e.g. UK Mac Alt-3 → `#`, US Mac Alt-2 → `™`). In that case the composed character is treated as typed input, since blocking it would make those characters untypeable on layouts that need a modifier to produce them. Bare characters are consumed for typing.

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

### sub next-word-pos

```raku
sub next-word-pos(
    Str:D $s,
    Int:D $pos
) returns Int
```

Find the position of the start of the next word at or after `$pos` in `$s`. Word = run of `\w` chars. Skips through the current char's class (word or non-word), then through any trailing non-word chars, landing at the first word char of the next word — or `$s.chars` if there is no next word. Used by shift-right word-jump and by `MultiLineInput`'s 2D variant.

### sub prev-word-pos

```raku
sub prev-word-pos(
    Str:D $s,
    Int:D $pos
) returns Int
```

Find the position of the start of the previous word at or before `$pos` in `$s`. Skips backwards through any non-word chars, then backwards through word chars, landing on the index of the first char of that word — or 0 if we walked off the start. Used by shift-left and shift-backspace.

### method insert-text

```raku
method insert-text(
    Str:D $text
) returns Nil
```

Insert `$text` at the current cursor position in one operation. Equivalent to typing each character in turn, but does ONE buffer concat instead of one per char — drops paste cost from O(n²) to O(n). Newlines and other control chars in `$text` are stripped (single-line input). Used by the App's paste-batching drain loop; application code can call it directly to programmatically insert text.

