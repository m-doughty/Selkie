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

Four Supplies:

  * `on-submit` — fires once when the user presses Enter, carrying the current text

  * `on-change` — fires on every keystroke that modifies the buffer

  * `on-copy` — fires on Ctrl+C, carrying the currently-selected text

  * `on-cut` — fires on Ctrl+X, carrying the cut text (which is also deleted from the buffer)

For programmatic updates that shouldn't re-dispatch (e.g. syncing from a store subscription), use `set-text-silent` — it updates the buffer without emitting on `on-change`.

Mouse and selection
-------------------

Click positions the caret. Drag selects from the press point to the current cursor cell — the selection range is rendered with reverse-video. Double-click selects the word under the cursor; triple-click selects the entire buffer. `has-selection`, `selection-range`, and `selected-text` expose the current selection state.

Keyboard cooperates: Shift+Left / Shift+Right jump by word AND extend the selection (the legacy word-jump is now also a selection-extend); plain arrows clear any selection before moving. Ctrl+A selects all. Ctrl+C and Ctrl+X emit on the corresponding supplies — Selkie does not own the system clipboard, so apps wire OSC 52 / notcurses paste-buffer in their handlers. Backspace and Delete delete an active selection if present; typing replaces it.

Modifier bubbling
-----------------

Modified keys (Ctrl, Alt, Super) bubble past the input so global keybinds still work — except for Ctrl+A / C / X (selection-related, handled internally) and except when the OS keyboard layout has already composed the modifier into a different printable character (e.g. UK Mac Alt-3 → `#`, US Mac Alt-2 → `™`). In that case the composed character is treated as typed input, since blocking it would make those characters untypeable on layouts that need a modifier to produce them. Bare characters are consumed for typing.

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

### has Int $!sel-anchor

Selection anchor offset. -1 means "no selection" — the cursor is a bare caret. When >= 0, the selection covers the half-open range from `min(anchor, cursor)` to `max(anchor, cursor)`. The cursor is the movable end; the anchor stays put while extending.

### method has-selection

```raku
method has-selection() returns Bool
```

True iff there is an active selection (anchor differs from cursor). A bare caret returns False.

### method selection-range

```raku
method selection-range() returns Range
```

Half-open offset range of the current selection, normalised to `low..^high`. Returns `0..^0` when there's no selection.

### method selected-text

```raku
method selected-text() returns Str
```

The substring currently selected, or the empty string when there is no selection.

### method clear-selection

```raku
method clear-selection() returns Mu
```

Clear any active selection without moving the caret.

### method on-copy

```raku
method on-copy() returns Supply
```

Supply emitting the currently-selected text on Ctrl+C. The Selkie framework does not own the system clipboard — apps wire this up themselves via OSC 52 or notcurses paste-buffer. The supply only fires when there's an active selection.

### method on-cut

```raku
method on-cut() returns Supply
```

Supply emitting on Ctrl+X. Like on-copy but the selection is also deleted from the buffer.

### method insert-text

```raku
method insert-text(
    Str:D $text
) returns Nil
```

Insert `$text` at the current cursor position in one operation. Equivalent to typing each character in turn, but does ONE buffer concat instead of one per char — drops paste cost from O(n²) to O(n). Newlines and other control chars in `$text` are stripped (single-line input). Used by the App's paste-batching drain loop; application code can call it directly to programmatically insert text. If a selection is active, it is replaced (deleted then the new text is inserted at the deletion point) — matches the canonical "type to overwrite selection" behavior of every text editor.

