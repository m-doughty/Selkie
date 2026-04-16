NAME
====

Selkie::Widget::LineChart - Static multi-series line chart with axes and legend

SYNOPSIS
========

```raku
use Selkie::Widget::LineChart;
use Selkie::Sizing;

# Single series — auto-derives Y range from the data
my $cpu = Selkie::Widget::LineChart.new(
    series => [
        { label => 'cpu %', values => @cpu-history },
    ],
    sizing => Sizing.flex,
);

# Multi-series with explicit colours
my $cmp = Selkie::Widget::LineChart.new(
    series => [
        { label => 'p50', values => @p50, color => 0xE69F00 },
        { label => 'p99', values => @p99, color => 0xCC4444 },
    ],
    fill-below => True,
    sizing     => Sizing.flex,
);
```

DESCRIPTION
===========

A static-data line chart, hand-rolled with braille (U+2800-U+28FF) sub-cell resolution. Each cell holds 2×4 braille dots; lines are rasterised at 2× horizontal × 4× vertical resolution relative to the plain cell grid.

For **streaming** data, prefer [Selkie::Widget::Plot](Selkie--Widget--Plot.md) (uses the native ncuplot / ncdplot ring buffer; better at high sample rates). For one-row inline charts, use [Selkie::Widget::Sparkline](Selkie--Widget--Sparkline.md).

What it composes
----------------

Internally LineChart manages three regions:

  * **Body** — the chart area, drawn with braille dots

  * **Y axis** (left edge) — labels + tick marks, when `show-axis` is True

  * **Legend** (bottom strip) — colour-coded series labels, when `show-legend` is True and there's more than one series

Each region renders inline via direct ncplane calls; the widget doesn't compose child widgets. Disable axis/legend to reclaim the reserved cells and devote all cells to the body.

Multi-series colour collision
-----------------------------

Each braille cell renders with a single foreground colour. When two series cross in the same 2×4 sub-cell window, the last-drawn series' colour wins ("z-order"). Series are drawn in order; in practice this means the last series in your list "covers" earlier ones at intersections.

This is a fundamental limit of single-foreground terminal cells. For series that overlap heavily, a faceted layout (one chart per series, stacked) gives clearer attribution.

Range
-----

Y range auto-derives from `min(0, min-data)` to `max-data`. Pass explicit `:y-min` and `:y-max` to fix it. X is always slot indices `0 .. (max-series-length - 1)`; series of differing lengths are plotted against the full domain (longer series fill the X span, shorter series stop before the right edge).

Fill below
----------

Pass `:fill-below` to fill the area between each series line and the chart's baseline (the lower edge for positive-only data). Fill uses the `graph-fill` theme slot when the series has no color override; with multiple series the fill stacks visually with z-order priority.

EXAMPLES
========

Single static series
--------------------

```raku
my @samples = (^60).map: { sin($_ * 0.1) * 100 };
my $chart = Selkie::Widget::LineChart.new(
    series => [{ label => 'sine', values => @samples }],
    sizing => Sizing.flex,
);
```

Multi-series comparison
-----------------------

```raku
my $chart = Selkie::Widget::LineChart.new(
    series => [
        { label => 'reads',  values => @read-rate,  color => 0x4477AA },
        { label => 'writes', values => @write-rate, color => 0xEE6677 },
    ],
    sizing => Sizing.flex,
);
```

Fill-below for area emphasis
----------------------------

```raku
my $chart = Selkie::Widget::LineChart.new(
    series     => [{ label => 'load', values => @load-1m }],
    fill-below => True,
    y-min      => 0,
    y-max      => 4,
    sizing     => Sizing.flex,
);
```

Reactive — values bound to a store path
---------------------------------------

```raku
my $chart = Selkie::Widget::LineChart.new(
    store-path-fn => -> $store {
        [
            { label => 'series',
              values => $store.get-in('metrics', 'history') // [] },
        ]
    },
    sizing => Sizing.flex,
);
```

SEE ALSO
========

  * [Selkie::Widget::Plot](Selkie--Widget--Plot.md) — streaming variant backed by native ncuplot

  * [Selkie::Widget::Sparkline](Selkie--Widget--Sparkline.md) — single-row inline chart

  * [Selkie::Widget::ScatterPlot](Selkie--Widget--ScatterPlot.md) — points without lines (also braille)

  * [Selkie::Plot::Palette](Selkie--Plot--Palette.md) — series colour palettes

### has Positional @.series

List of series. Each entry is a hash with `label` (Str), `values` (Positional of Real), and optional `color` (UInt RGB).

### has Callable &.store-path-fn

Optional reactive data function: `sub ($store --` List)>. Called inside `render()` to derive series. Mutually exclusive with `series`. Useful when the data is computed from store state.

### has Str $.palette

Series-color palette name. Used when individual series don't specify `color`.

### has Bool $.show-axis

Whether to draw the Y axis. Disable to reclaim ~5 columns.

### has Bool $.show-legend

Whether to draw the legend below the chart. Auto-disabled if there's only one series. Disable to reclaim 1 row.

### has Bool $.fill-below

Whether to fill the area below each line down to the baseline.

### has Str $.overlap

How to handle cells where multiple series have dots. Currently only `z-order` is supported (last-drawn series wins the colour).

### has Real $.y-min

Optional explicit Y bounds. Auto-derived when unset.

### has UInt $.tick-count

Approximate tick count for the Y axis.

### has Str $.empty-message

Message rendered when there are no samples. The default is the expected startup state for monitoring dashboards. Set to the empty string to suppress.

