NAME
====

Selkie::Widget::RichText::Span - A fragment of styled text within a RichText

SYNOPSIS
========

```raku
use Selkie::Widget::RichText::Span;
use Selkie::Style;

my $span = Selkie::Widget::RichText::Span.new(
    text  => 'Error: ',
    style => Selkie::Style.new(fg => 0xFF5555, bold => True),
);
```

DESCRIPTION
===========

A simple value class — holds a string and an optional style. Used exclusively as an element in the array passed to `Selkie::Widget::RichText.set-content`. The RichText widget word-wraps across span boundaries while preserving each span's style on the characters it owns.

The class has its own file so that `unit class` can declare it without conflicting with `Selkie::Widget::RichText` itself.

SEE ALSO
========

  * [Selkie::Widget::RichText](Selkie--Widget--RichText.md) — the widget that renders a list of spans

  * [Selkie::Style](Selkie--Style.md) — styling attributes

### has Str $.text

The text content of the span. Required.

### has Selkie::Style $.style

Optional style. If undefined, the RichText's default theme style is used for this span.

