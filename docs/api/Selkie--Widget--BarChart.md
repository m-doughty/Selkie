NAME
====

Selkie::Widget::BarChart - Categorical bar chart, vertical or horizontal

SYNOPSIS
========

```raku
use Selkie::Widget::BarChart;
use Selkie::Sizing;

# Vertical bars (default)
my $bars = Selkie::Widget::BarChart.new(
    data => [
        { label => 'apples',  value => 12 },
        { label => 'pears',   value =>  7 },
        { label => 'cherries',value => 15 },
        { label => 'plums',   value =>  4 },
    ],
    sizing => Sizing.flex,
);

# Horizontal bars
my $hbars = Selkie::Widget::BarChart.new(
    data        => @data,
    orientation => 'horizontal',
    sizing      => Sizing.flex,
);

# Reactive — read from a store path
my $live = Selkie::Widget::BarChart.new(
    store-path => <stats counts>,
    sizing     => Sizing.flex,
);
```

DESCRIPTION
===========

A categorical bar chart. Each entry is a labelled value; entries are laid out across the chart body with one bar per entry. The **orientation** determines the bar direction:

  * **vertical** (default) — bars rise from the bottom; labels along the bottom edge; values along the left edge.

  * **horizontal** — bars extend rightward from the left; labels along the left edge; values along the top edge.

Bar heights / widths use 1/8-cell precision via the Unicode block glyphs (`▁▂▃▄▅▆▇█` vertically, `▏▎▍▌▋▊▉█` horizontally) so a bar can be `3.625` cells tall, not just integer cells.

Construction modes
------------------

Same as [Selkie::Widget::Sparkline](Selkie--Widget--Sparkline.md):

  * **Static** — pass `:data([...])` with one hash per bar (`label`, `value`, optional `color`).

  * **Reactive** — pass `:store-path<a b c>` to read the data array from a store path; the widget re-renders when the value changes.

The two modes are mutually exclusive.

Coloring
--------

Each bar's color comes from one of three sources, in priority order:

  * Per-bar override: `{ label =` 'foo', value => 12, color => 0xFF0000 }>

  * The named palette specified by `:palette` (default `okabe-ito`) — colors cycle if there are more bars than palette entries

  * `self.theme.graph-line` as a fallback for any bar without a color and no palette match

See [Selkie::Plot::Palette](Selkie--Plot--Palette.md) for the available palettes.

Range
-----

Y-range (vertical) / X-range (horizontal) auto-derives from the data: the lower bound is `0` (or the data minimum if negative), the upper bound is the data maximum padded outward by Heckbert's nice-number choice (so the top tick lands on a round number).

Pass `:min` and `:max` to fix the range.

EXAMPLES
========

Simple categorical comparison
-----------------------------

```raku
my $chart = Selkie::Widget::BarChart.new(
    data => [
        { label => 'Q1', value => 1230 },
        { label => 'Q2', value => 1875 },
        { label => 'Q3', value => 2042 },
        { label => 'Q4', value => 1611 },
    ],
    sizing => Sizing.flex,
);
```

Multi-color with a palette override
-----------------------------------

```raku
my $chart = Selkie::Widget::BarChart.new(
    data    => @data,
    palette => 'tol-bright',
    sizing  => Sizing.flex,
);
```

Per-bar color (status indicator)
--------------------------------

```raku
my @data = $tasks.map: -> $t {
    {
        label => $t.name,
        value => $t.duration-ms,
        color => $t.status eq 'failed' ?? 0xCC4444 !! 0x44AA44,
    }
};
my $chart = Selkie::Widget::BarChart.new(:@data, sizing => Sizing.flex);
```

SEE ALSO
========

  * [Selkie::Widget::Histogram](Selkie--Widget--Histogram.md) — bins a numeric series and feeds it into BarChart

  * [Selkie::Widget::Sparkline](Selkie--Widget--Sparkline.md) — for a single inline trend bar

  * [Selkie::Plot::Palette](Selkie--Plot--Palette.md) — series colors

### has Positional @.data

List of bar entries. Each entry is a hash with `label` (Str), `value` (Real), and optional `color` (UInt RGB).

### has Positional[Str] @.store-path

Reactive store path. Mutually exclusive with `data`.

### has Str $.orientation

`vertical` (bars rise from the bottom) or `horizontal` (bars extend right from the left).

### has Str $.palette

Named series palette for bar colors. See [Selkie::Plot::Palette](Selkie--Plot--Palette.md).

### has Bool $.show-axis

Whether to draw the value axis (left for vertical, top for horizontal). Disable when the chart is composed in a layout that supplies its own axis.

### has Bool $.show-labels

Whether to draw category labels (bottom for vertical, left for horizontal).

### has Real $.min

Optional explicit lower bound. When unset, derived from the data (`min(0, min-data)`).

### has Real $.max

Optional explicit upper bound. When unset, derived from the data (`max-data`, padded by Heckbert).

### has UInt $.tick-count

Approximate tick count for the value axis.

### has Str $.empty-message

Message rendered when there are no bars. The default is the expected startup state for monitoring dashboards. Set to the empty string to suppress.

