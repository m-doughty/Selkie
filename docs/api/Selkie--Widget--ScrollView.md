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
```

DESCRIPTION
===========

A container that renders only the rows of its children currently in view. Children report their `logical-height`; ScrollView uses this to compute scrollable extent and render the correct slice via `render-region`.

Arrow keys, PageUp/PageDown, Home/End, and the mouse wheel scroll when the widget is focused. A scrollbar appears on the right edge when content is taller than the viewport.

Children should implement `logical-height` and, ideally, `render-region(offset, height)`. `Text`, `RichText`, and `TextStream` do. Plain widgets that don't will be rendered at full height — fine for short children.

SEE ALSO
========

  * [Selkie::Widget::TextStream](Selkie--Widget--TextStream.md) — scrollable log with its own ring buffer

  * [Selkie::Widget::CardList](Selkie--Widget--CardList.md) — interactive variable-height list

