NAME
====

Selkie::Widget::Heatmap - Coloured grid for 2D numeric data

SYNOPSIS
========

```raku
use Selkie::Widget::Heatmap;
use Selkie::Sizing;

# A 4×4 grid of arbitrary numeric values. Each cell renders as a
# coloured block; colour comes from the viridis ramp by default.
my $h = Selkie::Widget::Heatmap.new(
    data => [
        [ 0.1, 0.3, 0.5, 0.7 ],
        [ 0.2, 0.4, 0.6, 0.8 ],
        [ 0.3, 0.5, 0.7, 0.9 ],
        [ 0.4, 0.6, 0.8, 1.0 ],
    ],
    sizing => Sizing.fixed(4),
);

# Custom ramp + explicit range (useful for diverging data around 0)
my $diverging = Selkie::Widget::Heatmap.new(
    data   => @correlation-matrix,
    ramp   => 'coolwarm',
    min    => -1.0,
    max    =>  1.0,
    sizing => Sizing.flex,
);

# Reactive
my $live = Selkie::Widget::Heatmap.new(
    store-path => <metrics utilization-grid>,
    sizing     => Sizing.flex,
);
```

DESCRIPTION
===========

A heatmap renders a 2D grid of numeric values as a grid of coloured cells. Each cell is filled with `█` (full block); the foreground colour comes from a ramp lookup keyed by the cell's value normalised to `[0, 1]`.

Colour ramps
------------

Default ramp is `viridis` (perceptually uniform, colourblind-safe). Other ramps from [Selkie::Plot::Palette](Selkie--Plot--Palette.md):

  * `viridis` — purple → blue → teal → green → yellow

  * `magma` — black → purple → magenta → cream

  * `plasma` — deep blue → magenta → orange

  * `coolwarm` — diverging blue → white → red, useful for signed data centred on zero

  * `grayscale` — five steps of grey, accessibility fallback

Override per-widget with `:ramp<name>`.

Range
-----

By default the range `[min, max]` auto-derives from the data extent. Pass explicit `:min` / `:max` to fix it (essential for the diverging `coolwarm` ramp, where `0` needs to map to the white midpoint regardless of data extent).

`NaN` values render with the `text-dim` theme slot so missing data is visually distinct from in-range zero.

Cell aspect ratio
-----------------

Terminal cells are taller than they are wide (~2:1). Heatmaps **don't compensate for this** — each data cell renders as one terminal cell, so a 10×10 data grid looks tall and narrow on screen. To get a near-square render, double the columns (repeat each cell horizontally) by pre-processing the data.

EXAMPLES
========

A 2D function evaluation
------------------------

```raku
my @grid = (^16).map: -> $r {
    (^16).map: -> $c {
        my $x = ($c - 8) / 8;
        my $y = ($r - 8) / 8;
        sin(sqrt($x*$x + $y*$y) * 5);
    }
};

my $heatmap = Selkie::Widget::Heatmap.new(
    data   => @grid,
    ramp   => 'viridis',
    sizing => Sizing.fixed(16),
);
```

A correlation matrix with a diverging ramp
------------------------------------------

Diverging ramps map `0` to white in the middle. Pin the range to keep the centre stable as data updates:

```raku
my $heatmap = Selkie::Widget::Heatmap.new(
    data   => @corr-matrix,         # values in [-1, 1]
    ramp   => 'coolwarm',
    min    => -1,
    max    =>  1,
    sizing => Sizing.fixed(@corr-matrix.elems),
);
```

Custom palette via theme override
---------------------------------

The ramp comes from [Selkie::Plot::Palette](Selkie--Plot--Palette.md). To use a colour ramp not included in Palette, render a custom heatmap by subclassing this widget — or open a feature request to add the ramp to Palette upstream.

SEE ALSO
========

  * [Selkie::Plot::Palette](Selkie--Plot--Palette.md) — the colour ramp definitions

  * [Selkie::Widget::ScatterPlot](Selkie--Widget--ScatterPlot.md) — for sparse 2D point data

  * [Selkie::Widget::BarChart](Selkie--Widget--BarChart.md) — for 1D categorical data

### has Positional @.data

2D array of numeric values. Each row is one row of cells.

### has Positional[Str] @.store-path

Reactive store path. Mutually exclusive with `data`.

### has Str $.ramp

Named colour ramp from [Selkie::Plot::Palette](Selkie--Plot--Palette.md). Default: `viridis`.

### has Real $.min

Optional explicit lower bound. Auto-derived from data when unset.

### has Real $.max

Optional explicit upper bound. Auto-derived from data when unset.

### has Str $.empty-message

Message rendered when there is no data. This is the expected startup state for monitoring dashboards. Set to the empty string to suppress.

