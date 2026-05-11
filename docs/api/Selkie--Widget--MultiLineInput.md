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

Mouse and selection
-------------------

Click positions the caret. Drag selects across rows; the selection range is rendered with reverse-video and respects word-wrap (the highlight follows the wrapped layout, not raw offsets). Double-click selects the word under the cursor; triple-click selects the entire current logical line. Scroll-wheel moves the cursor up/down. Ctrl+A selects everything; Ctrl+C / Ctrl+X emit on `on-copy` / `on-cut` and (for cut) delete the selection. Backspace and Delete consume an active selection if present; typing replaces it.

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

### has Int $!sel-anchor-row

Selection anchor in (logical-row, logical-col). `-1` in $!sel-anchor-row means "no selection" — cursor is a bare caret. When >= 0 the selection covers the half-open range from `min(anchor, cursor)` to `max(anchor, cursor)`, walked across logical lines.

### method has-selection

```raku
method has-selection() returns Bool
```

True iff a selection is active (anchor differs from cursor). Bare caret returns False.

### method selection-range

```raku
method selection-range() returns List
```

Returns the normalised selection range as a List of two pairs: `(:row, :col)` for the start and `(:row, :col)` for the end (half-open at end). Returns `()` when no selection.

### method selected-text

```raku
method selected-text() returns Str
```

The text currently selected, walking line by line. `\n` joins successive logical lines. Empty string when no selection.

### method clear-selection

```raku
method clear-selection() returns Mu
```

Clear the active selection without moving the caret.

### method on-copy

```raku
method on-copy() returns Supply
```

Supply emitting the currently-selected text on Ctrl+C. Selkie does not own the system clipboard — apps wire this up themselves via OSC 52 or notcurses paste-buffer. Fires only when there's an active selection.

### method on-cut

```raku
method on-cut() returns Supply
```

Supply emitting on Ctrl+X. Like `on-copy` but the selection is also deleted from the buffer.

### method text

```raku
method text() returns Str
```

The full buffer contents joined with `\n`. (The buffer is stored as an array of logical lines; this assembly is O(N) in total character count — cache the result if calling per frame.)

### method set-text

```raku
method set-text(
    Str:D $t
) returns Mu
```

Replace the buffer contents and place the caret at the end. Emits on `on-change`. Use this for user-driven updates; for programmatic syncs from a store path use `set-text-silent` instead to avoid feedback loops.

### method set-text-silent

```raku
method set-text-silent(
    Str:D $t
) returns Mu
```

Silent variant of `set-text` — updates the buffer without emitting on `on-change`. Wire this into store subscriptions that mirror external state into the input, so the input update doesn't dispatch an event that loops back through the store and re-fires the subscription.

### method clear

```raku
method clear() returns Mu
```

Empty the buffer. Equivalent to `set-text('')`.

### method on-submit

```raku
method on-submit() returns Supply
```

Supply that emits the current buffer when the user presses Ctrl+Enter (Enter inserts a newline). Apps that want plain Enter as submit register their own keybind and call `text` directly.

### method on-change

```raku
method on-change() returns Supply
```

Supply that emits the new buffer contents on every user-driven edit (typing, paste, delete, cut, `set-text`). Does not fire for `set-text-silent`.

### method set-focused

```raku
method set-focused(
    Bool $f
) returns Mu
```

Set the input's focus state. Called by `Selkie::App`'s focus dispatcher. The caret is only painted while focused.

### method is-focused

```raku
method is-focused() returns Bool
```

Whether the widget currently has focus.

### method desired-height

```raku
method desired-height() returns UInt
```

The natural visual height for the buffer in cells, accounting for soft-wrap at the current width. Clamped to `max-lines`. Used by autosize containers (e.g. a chat compose area) to grow the input with its content.

### method line-count

```raku
method line-count() returns UInt
```

Number of logical lines in the buffer (counts hard newlines, not soft-wraps). Always at least 1 — an empty buffer counts as one empty line.

### method cursor-row

```raku
method cursor-row() returns UInt
```

Caret row in logical-line coordinates (0-based; counts hard newlines, not soft-wraps).

### method cursor-col

```raku
method cursor-col() returns UInt
```

Caret column on the current logical line (0-based; counts characters, not visual cells).

### method visual-rows

```raku
method visual-rows() returns Array
```

Same shape as `!visual-lines`, but each entry is a hash with `logical-row`, `logical-col-start`, `text`. Used by the selection overlay to map visual rows back to logical (row, col) spans for highlighting.

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

