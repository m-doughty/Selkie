NAME
====

Selkie::Layout::VBox - Arrange children top to bottom

SYNOPSIS
========

```raku
use Selkie::Layout::VBox;
use Selkie::Sizing;

my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$vbox.add: $header;    # Sizing.fixed(1)
$vbox.add: $body;      # Sizing.flex
$vbox.add: $footer;    # Sizing.fixed(1)
```

DESCRIPTION
===========

`VBox` stacks children vertically and allocates rows according to each child's [Selkie::Sizing](Selkie--Sizing.md):

  * **Fixed** children get exactly the rows they ask for.

  * **Percent** children get `n%` of the parent's total rows.

  * **Flex** children share whatever rows are left over, weighted by flex factor.

Columns are set to the full parent width for every child.

VBox is a [Selkie::Container](Selkie--Container.md), so it inherits `add`, `remove`, `clear`, and focusable-descendants handling. All children must compose `Selkie::Widget`.

EXAMPLES
========

Classic three-pane stack
------------------------

```raku
my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);

$root.add: Selkie::Widget::Text.new(
    text   => ' Selkie App',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

$root.add: $main-content;   # sizing => Sizing.flex — fills middle

$root.add: Selkie::Widget::Text.new(
    text   => ' Ctrl+Q: quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x666666),
);
```

Weighted distribution
---------------------

```raku
my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$vbox.add: $preview;   # Sizing.flex(2) — gets two-thirds
$vbox.add: $output;    # Sizing.flex    — gets one-third
```

SEE ALSO
========

  * [Selkie::Layout::HBox](Selkie--Layout--HBox.md) — horizontal version of the same layout

  * [Selkie::Layout::Split](Selkie--Layout--Split.md) — two-pane split with a draggable divider ratio

  * [Selkie::Sizing](Selkie--Sizing.md) — the fixed/percent/flex sizing model

### method render

```raku
method render() returns Mu
```

Perform layout and render each child. Called automatically by the render cycle. The layout pass allocates rows according to every child's `Sizing`: fixed first, then percent, then flex shares the rest.

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Resize cascade: own plane + re-layout children so allocations propagate synchronously through the subtree, without waiting for the next render pass. Layout-children calls handle-resize on each child so the recursion continues.

