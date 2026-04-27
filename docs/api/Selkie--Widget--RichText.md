NAME
====

Selkie::Widget::RichText - Styled text built from `Span` fragments

SYNOPSIS
========

```raku
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Style;
use Selkie::Sizing;

my $rich = Selkie::Widget::RichText.new(sizing => Sizing.flex);
$rich.set-content([
    Selkie::Widget::RichText::Span.new(
        text  => 'alice: ',
        style => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    ),
    Selkie::Widget::RichText::Span.new(
        text  => 'Hey, how are you?',
        style => Selkie::Style.new(fg => 0xEEEEEE),
    ),
]);
```

DESCRIPTION
===========

Like [Selkie::Widget::Text](Selkie--Widget--Text.md), but each fragment can have its own style. Word-wraps across span boundaries while preserving styles — if a span is split across two lines, both halves render with that span's style.

Supports partial rendering via `render-region`, so it composes correctly inside `Selkie::Widget::ScrollView`. The `truncated-top` and `truncated-bottom` flags insert "…" ellipsis lines when content would overflow — useful for showing a preview snippet.

EXAMPLES
========

Colour-coded message
--------------------

```raku
my $red = Selkie::Style.new(fg => 0xFF5555, bold => True);
$rich.set-content([
    Selkie::Widget::RichText::Span.new(text => 'Error: ', style => $red),
    Selkie::Widget::RichText::Span.new(text => 'file not found'),
]);
```

Truncated preview
-----------------

```raku
my $preview = Selkie::Widget::RichText.new(
    sizing           => Sizing.fixed(3),
    truncated-bottom => True,
);
# Content longer than 3 lines shows the first 2 lines + '…'
```

Pre-rendering line count
------------------------

```raku
# Static wrap — lets variable-height container layouts size their
# slot to the exact rendered line count BEFORE the widget is
# attached to a plane. The same algorithm the live renderer uses,
# so card height matches render height to the row.
my @lines = Selkie::Widget::RichText.wrap-spans(@spans, 60);
say @lines.elems;   # exact wrapped-line count at width 60
```

SEE ALSO
========

  * [Selkie::Widget::RichText::Span](Selkie--Widget--RichText--Span.md) — the fragment value class

  * [Selkie::Widget::Text](Selkie--Widget--Text.md) — simpler, single-style variant

  * [Selkie::Widget::ScrollView](Selkie--Widget--ScrollView.md) — for scrolling long rich text

### has Bool $.truncated-bottom

When set to True, overflow at the bottom is shown as a "…" line in place of the last visible wrapped line.

### has Bool $.truncated-top

When True, overflow at the top is shown as a "…" line in place of the first visible wrapped line (displays the most recent content).

### method set-content

```raku
method set-content(
    @spans
) returns Mu
```

Replace the displayed content with the given list of Spans. The wrap cache is invalidated; the next render rebuilds it.

### method spans

```raku
method spans() returns List
```

The current spans as a List.

### method logical-height

```raku
method logical-height() returns UInt
```

Number of wrapped lines at the current width. Used by ScrollView.

### method wrap-spans

```raku
method wrap-spans(
    @spans,
    Int $width where { ... }
) returns Array
```

Pure word-wrap: take a list of Spans and a target width, return the wrapped-line array (each element is an Array[Span]). Same algorithm the live renderer uses via `!rewrap`, exposed as a class method so consumers that need the exact line count without attaching a plane (e.g. variable-height card layouts) can size themselves accurately. Always returns at least one (possibly empty) line.

