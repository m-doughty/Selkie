NAME
====

Selkie::Widget::Legend - Color-swatch + label rows for chart series

SYNOPSIS
========

```raku
use Selkie::Widget::Legend;
use Selkie::Sizing;

# A vertical legend with three series. Each row is "■ label".
my $legend = Selkie::Widget::Legend.new(
    series      => [
        { label => 'cpu',     color => 0xE69F00 },
        { label => 'memory',  color => 0x56B4E9 },
        { label => 'iowait',  color => 0x009E73 },
    ],
    orientation => 'vertical',
    sizing      => Sizing.fixed(3),
);

# A horizontal legend — series laid out across one row, separated by spaces.
my $h-legend = Selkie::Widget::Legend.new(
    series      => @series,
    orientation => 'horizontal',
    sizing      => Sizing.fixed(1),
);
```

DESCRIPTION
===========

Renders a color-coded series legend for chart widgets. Each entry is a coloured swatch glyph (`■`) followed by the series label. Labels that don't fit are truncated with an ellipsis.

The legend is theme-aware: the swatch colors come from each series' `color` entry; label text uses `self.theme.text`; the optional background derives from `self.theme.graph-legend-bg`.

Orientations
------------

  * **vertical** (default) — one series per row. Used in dashboards where the legend lives in a sidebar or column.

  * **horizontal** — series laid out left-to-right separated by single spaces. Best for legends below a chart.

Truncation
----------

When a label doesn't fit (the swatch + label exceeds the available cells in its row/column), the label is truncated and ellipsised (`…`). For horizontal layouts that means the rightmost series get clipped first; for vertical, individual labels are clipped per row.

EXAMPLES
========

Inline with a LineChart
-----------------------

```raku
use Selkie::Widget::LineChart;
use Selkie::Widget::Legend;
use Selkie::Layout::HBox;
use Selkie::Sizing;

my @series = (
    { label => 'p50', values => @p50, color => 0x4477AA },
    { label => 'p99', values => @p99, color => 0xEE6677 },
);

my $chart = Selkie::Widget::LineChart.new(
    series       => @series,
    show-legend  => False,            # we'll draw our own
);

my $legend = Selkie::Widget::Legend.new(
    series       => @series,
    orientation  => 'vertical',
);

my $row = Selkie::Layout::HBox.new;
$row.add($chart,  sizing => Sizing.flex);
$row.add($legend, sizing => Sizing.fixed(12));
```

Below a chart, single-row horizontal
------------------------------------

```raku
my $legend = Selkie::Widget::Legend.new(
    series      => @series,
    orientation => 'horizontal',
    sizing      => Sizing.fixed(1),
);

my $stack = Selkie::Layout::VBox.new;
$stack.add($chart,  sizing => Sizing.flex);
$stack.add($legend, sizing => Sizing.fixed(1));
```

SEE ALSO
========

  * [Selkie::Plot::Palette](Selkie--Plot--Palette.md) — colorblind-safe series palettes for the `color` entries

  * [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) — composes a Legend internally when `show-legend` is True

  * [Selkie::Widget::BarChart](Selkie--Widget--BarChart.md)

### has Positional @.series

List of series entries. Each entry is a hash with `label` (Str) and `color` (UInt RGB). Order is rendering order — first entry is at top (vertical) or left (horizontal).

### has Str $.orientation

`vertical` (one row per series) or `horizontal` (single row, series separated by single spaces).

### has Str $.swatch

Glyph used for the color swatch. Defaults to a full block (`■` — U+25A0). Some terminals render this slightly narrower than ideal; `●` (U+25CF) and `█` (U+2588) are common alternates.

### method set-series

```raku
method set-series(
    @new
) returns Mu
```

Replace the series list and request a re-render.

