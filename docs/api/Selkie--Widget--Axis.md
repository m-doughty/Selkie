NAME
====

Selkie::Widget::Axis - Labelled tick axis for chart widgets

SYNOPSIS
========

```raku
use Selkie::Widget::Axis;
use Selkie::Sizing;

# A bottom axis covering [0, 100] with five ticks.
my $axis = Selkie::Widget::Axis.new(
    edge       => 'bottom',
    min        => 0,
    max        => 100,
    tick-count => 5,
    sizing     => Sizing.fixed(2),    # 1 row line + 1 row labels
);

# A left axis for a y-axis; reserves 5 columns by default for labels.
my $left = Selkie::Widget::Axis.new(
    edge       => 'left',
    min        => 0,
    max        => 1.0,
    tick-count => 6,
    sizing     => Sizing.fixed(6),
);
```

DESCRIPTION
===========

Renders a labelled axis along one of the four edges of its plane: `top`, `bottom`, `left`, or `right`. The axis is the visual companion to chart widgets — a horizontal axis sits below a chart body, a vertical axis sits to its left or right.

Internally the axis builds its own [Selkie::Plot::Scaler](Selkie--Plot--Scaler.md) and [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md) matched to its current plane dimensions. So when a chart widget composes an Axis, it just passes the axis's data range (min, max) and tick count — the axis figures out its own cell mapping.

Y-axes (`left`, `right`) automatically use `:invert` so the maximum value sits at the top of the plane (terminal row 0 is the *top* of the screen, which by chart convention should hold the largest value).

Glyphs
------

The four edges use these box-drawing glyphs:

<table class="pod-table">
<tbody>
<tr> <td>Edge</td> <td>Line</td> <td>Tick</td> <td>Label position</td> </tr> <tr> <td>bottom</td> <td>─</td> <td>┬</td> <td>row below the line, centred on the tick column</td> </tr> <tr> <td>top</td> <td>─</td> <td>┴</td> <td>row above the line, centred on the tick column</td> </tr> <tr> <td>left</td> <td>│</td> <td>┤</td> <td>columns to the left of the line, right-aligned to the tick row</td> </tr> <tr> <td>right</td> <td>│</td> <td>├</td> <td>columns to the right of the line, left-aligned to the tick row</td> </tr>
</tbody>
</table>

All glyphs render in the `graph-axis` theme slot; labels render in `graph-axis-label`. Override either per-theme or via custom slots to restyle.

Sizing
------

  * **Top / bottom** axes need 2 rows: one for the line and one for labels. `reserved-rows` returns 2.

  * **Left / right** axes need `widest-label + 1` columns: the labels plus the line. Width depends on the data range — call `reserved-cols` to get the actual budget.

Use these helpers when sizing parent containers so the axis gets exactly the rows / columns it needs:

```raku
my $axis = Selkie::Widget::Axis.new(edge => 'left', min => 0, max => 1000);
$container.add: $axis, sizing => Sizing.fixed($axis.reserved-cols);
```

EXAMPLES
========

A standalone bottom axis
------------------------

```raku
use Selkie::Widget::Axis;
use Selkie::Sizing;

my $axis = Selkie::Widget::Axis.new(
    edge       => 'bottom',
    min        => 0,
    max        => 1000,
    tick-count => 5,
    sizing     => Sizing.fixed(2),
);

# Drop into a VBox above other content, or into a chart widget that
# delegates the bottom strip to it.
```

Composed inside a chart layout
------------------------------

A chart usually composes a bottom axis below the body and a left axis to its left:

```raku
use Selkie::Widget::Axis;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;

my $left   = Selkie::Widget::Axis.new(edge => 'left',   min => 0, max => 100);
my $bottom = Selkie::Widget::Axis.new(edge => 'bottom', min => 0, max => 60);

my $body = my-chart-body();   # a LineChart, BarChart, etc.

my $row    = Selkie::Layout::HBox.new;
$row.add: $left, sizing => Sizing.fixed($left.reserved-cols);
$row.add: $body, sizing => Sizing.flex;

my $stack  = Selkie::Layout::VBox.new;
$stack.add: $row,    sizing => Sizing.flex;
$stack.add: $bottom, sizing => Sizing.fixed($bottom.reserved-rows);
```

SEE ALSO
========

  * [Selkie::Plot::Scaler](Selkie--Plot--Scaler.md) — the value→cell mapping the axis uses

  * [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md) — the nice-number tick generation

  * [Selkie::Charts](Selkie--Charts.md) — overview of the chart family

### has Str $.edge

Which edge to render on: `top`, `bottom`, `left`, or `right`.

### has Real $.min

Lower bound of the axis range.

### has Real $.max

Upper bound of the axis range.

### has UInt $.tick-count

Approximate tick count; the actual count depends on Heckbert's nice-number choice (see [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md)).

### has Bool $.show-line

Whether to draw the connecting axis line. Disable when stacking multiple axes on the same edge or when the chart body provides its own border.

### method reserved-rows

```raku
method reserved-rows() returns UInt
```

Number of rows this axis needs to render properly. Returns 2 for horizontal axes (line + labels), 0 for vertical (caller decides height). Use to size the axis's container correctly.

### method reserved-cols

```raku
method reserved-cols() returns UInt
```

Number of columns this axis needs to render properly. For vertical axes, returns the widest tick label's width plus one (for the axis line). For horizontal axes, returns 0 (caller decides width).

