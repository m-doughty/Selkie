NAME
====

Selkie::Widget::MultiLineInput - Multi-line text input with word-wrap and 2D cursor

SYNOPSIS
========

```raku
use Selkie::Widget::MultiLineInput;
use Selkie::Sizing;

my $area = Selkie::Widget::MultiLineInput.new(
    sizing      => Sizing.fixed(1),    # grows up to max-lines as user types
    max-lines   => 6,
    placeholder => 'Type a message... (Ctrl+Enter to send)',
);

$area.on-submit.tap: -> $text { send-message($text); $area.clear };
$area.on-change.tap: -> $text { save-draft($text) };
```

DESCRIPTION
===========

A multi-line text area with word-wrapping, a 2D cursor, and dynamic height that grows as the user types (up to `max-lines`). Plain `Enter` inserts a newline; `Ctrl+Enter` submits.

The height auto-adjusts via `desired-height`: if you pass `sizing =` Sizing.fixed(1)>, the parent layout sees the widget's desired height grow as content is added, bounded by `max-lines`.

`set-text-silent` updates the buffer without emitting `on-change` — use this from store subscriptions to avoid feedback loops.

EXAMPLES
========

Chat compose area
-----------------

```raku
my $compose = Selkie::Widget::MultiLineInput.new(
    sizing      => Sizing.fixed(1),
    max-lines   => 5,
    placeholder => 'Type a message — Ctrl+Enter to send',
);
$compose.on-submit.tap: -> $text {
    if $text.chars > 0 {
        $app.store.dispatch('chat/send', :$text);
        $compose.clear;
    }
};
```

SEE ALSO
========

  * [Selkie::Widget::TextInput](Selkie--Widget--TextInput.md) — single-line variant

  * [Selkie::Widget::TextStream](Selkie--Widget--TextStream.md) — append-only log (no editing)

### method insert-text

```raku
method insert-text(
    Str:D $text
) returns Nil
```

Insert `$text` at the current cursor position in one operation, splitting on `\n` so multi-line pasted content lays across multiple buffer lines. Equivalent to typing each character in turn but with one buffer rebuild instead of one per char — O(n) total instead of O(n²). Used by the App's paste-batching drain loop.

### method move-word-left

```raku
method move-word-left() returns Mu
```

Shift-Left: jump to the start of the current or previous word. When the cursor is at column 0, the jump crosses the line boundary and lands at the start of the last word on the previous line (or column 0 of that line if the previous line is empty).

### method move-word-right

```raku
method move-word-right() returns Mu
```

Shift-Right: jump to the start of the next word. When the cursor is at the end of the current line, the jump crosses to column 0 of the next line.

### method do-word-backspace

```raku
method do-word-backspace() returns Mu
```

Shift-Backspace: delete from the cursor back to the previous word boundary. At column 0, falls through to the regular backspace semantics so the line above is joined — matches what users expect from "delete previous word" in editors that also support multi-line.

