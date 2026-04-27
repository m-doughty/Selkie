NAME
====

Selkie::Widget::ScrollView - Virtual-scrolling container for long content

SYNOPSIS
========

```raku
use Selkie::Widget::ScrollView;
use Selkie::Widget::Text;
use Selkie::Sizing;

my $scroll = Selkie::Widget::ScrollView.new(sizing => Sizing.flex);
my $body = Selkie::Widget::Text.new(
    text   => slurp('long-document.txt'),
    sizing => Sizing.flex,
);
$scroll.add($body);

# Pin to bottom for streaming / log views — auto-scroll to keep the
# newest content visible until the user scrolls up.
my $tail = Selkie::Widget::ScrollView.new(
    sizing        => Sizing.flex,
    follow-bottom => True,
);
```

DESCRIPTION
===========

A container that renders only the rows of its children currently in view. Children report their `logical-height`; ScrollView uses this to compute scrollable extent and renders the correct slice via `render-region`.

Arrow keys, PgUp/PgDown, Home/End, and the mouse wheel scroll when the widget is focused. A scrollbar appears on the right edge when content is taller than the viewport.

The scrollbar's column is reserved unconditionally when `show-scrollbar` is True, even when no scrollbar is currently shown — this prevents the wrap-feedback loop where adding a scrollbar narrows the body, the body rewraps to one extra line, the new line overflows, and the row gets clipped under the scrollbar. The cost is one column of right-edge real-estate when content fits; the benefit is the slot is always sized for the worst case so content never truncates unexpectedly.

`follow-bottom` turns ScrollView into a tail-following pane: each render captures whether the user was at the bottom before content changed, and if so, snaps the new scroll offset to the new max so the latest content stays visible. Designed for log views and streaming-text bodies. Any scroll-up by the user disables the follow until they scroll back to the bottom.

Children should implement `logical-height` and, ideally, `render-region(offset, height)`. `Text`, `RichText`, and `TextStream` do. Plain widgets that don't will be rendered at full height — fine for short children.

SEE ALSO
========

  * [Selkie::Widget::TextStream](Selkie--Widget--TextStream.md) — scrollable log with its own ring buffer

  * [Selkie::Widget::CardList](Selkie--Widget--CardList.md) — interactive variable-height list

### has Bool $.follow-bottom

Auto-pin to the bottom of content as it grows. When True, each render checks whether the scroll offset was at `max-offset` just before `update-content-height` ran; if so, it snaps the new offset to the new `max-offset`. Streaming additions stay visible without manual scrolling. When False, scroll position is preserved across content changes (with clamping).

### method scroll-page-by

```raku
method scroll-page-by(
    Int $direction
) returns Mu
```

Scroll by one viewport-height in the given `$direction` (typically `+1` for PgDown, `-1` for PgUp). Centralises the "what does a page mean" decision in the ScrollView itself — callers don't need to query viewport-height first.

### method content-width

```raku
method content-width() returns UInt
```

Width available to children, exclusive of the reserved scrollbar column. Reserved unconditionally when `show-scrollbar` is True so children's wrapping is stable across scrollbar visibility changes. See class docs for the rationale.

