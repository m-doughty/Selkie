NAME
====

Selkie::Widget::Text - Static styled text with word-wrap

SYNOPSIS
========

```raku
use Selkie::Widget::Text;
use Selkie::Style;
use Selkie::Sizing;

my $header = Selkie::Widget::Text.new(
    text   => ' My App',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Mutate later
$header.set-text(' My App — logged in as Alice');
```

DESCRIPTION
===========

A block of text rendered onto a single plane. Word-wraps automatically when the text exceeds the widget's width — words longer than the line are hard-broken at the character level.

Styled via the optional `style` attribute. If omitted, inherits the theme's `text` slot.

`Text` implements `render-region(offset, height)`, so it plays correctly with `Selkie::Widget::ScrollView` for long content.

EXAMPLES
========

A header and footer
-------------------

```raku
$vbox.add: Selkie::Widget::Text.new(
    text   => 'Selkie App',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);
$vbox.add: $main-content;
$vbox.add: Selkie::Widget::Text.new(
    text   => 'Ctrl+Q: quit  —  ?: help',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x888888),
);
```

Driven by the store
-------------------

Set up a subscription that updates the text whenever state changes:

```raku
my $status = Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));
$app.store.subscribe-with-callback(
    'status-line',
    -> $s { "{$s.get-in('user', 'name') // 'guest'} — {$s.get-in('messages').elems} unread" },
    -> $text { $status.set-text($text) },
    $status,
);
```

SEE ALSO
========

  * [Selkie::Widget::RichText](Selkie--Widget--RichText.md) — styled spans within one block of text

  * [Selkie::Widget::TextStream](Selkie--Widget--TextStream.md) — append-only log with ring buffer and auto-scroll

### has Str $.text

The text to render. Can include newlines — each line is wrapped independently.

### has Selkie::Style $.style

Optional style override. If undefined, the theme's `text` slot is used.

### method set-text

```raku
method set-text(
    Str:D $t
) returns Mu
```

Replace the displayed text. Re-wraps and marks the widget dirty.

### method set-style

```raku
method set-style(
    Selkie::Style $s
) returns Mu
```

Replace the style override. Pass an undefined Selkie::Style to revert to the theme default.

### method logical-height

```raku
method logical-height() returns UInt
```

Number of lines the text wraps to at the current width. Used by `ScrollView` to compute scrollable extent.

### method render-region

```raku
method render-region(
    Int :$offset where { ... },
    Int :$height where { ... }
) returns Mu
```

Render only a slice of the wrapped lines, starting at `offset` and going for `height` rows. Used by `ScrollView` for partial-viewport rendering.

