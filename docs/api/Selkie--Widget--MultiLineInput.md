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

