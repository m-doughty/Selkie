NAME
====

Selkie::Widget::ScatterPlot - 2D point plot using braille sub-cell dots

SYNOPSIS
========

```raku
use Selkie::Widget::ScatterPlot;
use Selkie::Sizing;

# Single-series scatter — auto-derives axis ranges from the data.
# Points are Pairs (x => y) so Raku doesn't flatten the list.
my @points = (1..50).map: { (rand * 100) => (rand * 100) };
my $sp = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'samples', points => @points },
    ],
    sizing => Sizing.flex,
);

# Multi-series with explicit colours
my $sp2 = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'group A', points => @group-a, color => 0xE69F00 },
        { label => 'group B', points => @group-b, color => 0x56B4E9 },
    ],
    sizing => Sizing.flex,
);

# Tip: use Pair (x => y), [x, y] arrays, or hash {x => , y => } per
# point. Don't use bare lists `(x, y)` — Raku flattens them in
# array context and your single-point scatter becomes two
# independent values.

# Reactive
my $live = Selkie::Widget::ScatterPlot.new(
    store-path => <viz scatter-data>,
    sizing     => Sizing.flex,
);
```

DESCRIPTION
===========

A scatter plot of 2D points. Uses Unicode braille (U+2800-U+28FF) for **sub-cell** resolution: each terminal cell holds a 2×4 grid of dot positions (8 dots per cell). A 50-cell-wide plot can resolve 100 distinct x-positions, and a 20-cell-tall plot can resolve 80 distinct y-positions.

The braille dot grid
--------------------

Each braille codepoint encodes which of 8 sub-cell dots are filled:

    0 3
    1 4
    2 5
    6 7

The codepoint is `U+2800 + bit-pattern`, where bit N controls dot N. A cell with all 8 dots filled is `⣿` (U+28FF). A cell with no dots is `⠀` (U+2800).

Multi-series colour collision
-----------------------------

Each braille cell renders with a single foreground colour. When two series have dots in the same 2×4 sub-cell window, the cell's colour is determined by the `:overlap` setting:

  * `z-order` (default) — the last-drawn series wins the cell's colour. The earlier series' dots are still drawn but they take the later series' colour.

This is a documented limitation of single-foreground terminal rendering. For non-overlapping multi-series, the colour assignment is always correct. For overlapping data, prefer faceted layouts (separate scatter plots per series) over single-plot overlay.

Range
-----

Each axis range auto-derives from the data extent. Pass explicit `:x-min`, `:x-max`, `:y-min`, `:y-max` to fix any of them. Useful when streaming so the axes don't jitter as new points expand the range.

EXAMPLES
========

Single cluster
--------------

```raku
my @cluster = (1..50).map: {
    (50 + rand * 20 - 10, 50 + rand * 20 - 10);
};
my $sp = Selkie::Widget::ScatterPlot.new(
    series => [{ label => 'cluster', points => @cluster }],
    x-min  => 0, x-max => 100,
    y-min  => 0, y-max => 100,
    sizing => Sizing.flex,
);
```

Two clusters with distinct colours
----------------------------------

```raku
my $sp = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'cluster A', points => @a, color => 0xE69F00 },
        { label => 'cluster B', points => @b, color => 0x009E73 },
    ],
    sizing => Sizing.flex,
);
```

SEE ALSO
========

  * [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) — connects points with lines (also braille)

  * [Selkie::Widget::Heatmap](Selkie--Widget--Heatmap.md) — for 2D data on a regular grid

  * [Selkie::Plot::Palette](Selkie--Plot--Palette.md) — colourblind-safe series palettes

### has Positional @.series

List of series. Each series is a hash with `label` (Str), `points` (list of (x, y) pairs), and optional `color` (UInt RGB).

### has Positional[Str] @.store-path

Reactive store path. Mutually exclusive with `series`.

### has Str $.palette

Series-color palette. Used when individual series don't specify `color`.

### has Real $.x-min

Optional explicit X axis bounds. Auto-derived when unset.

### has Real $.y-min

Optional explicit Y axis bounds. Auto-derived when unset.

### has Str $.overlap

How to handle cells where multiple series have dots. Currently only `z-order` is supported (last-drawn wins the colour).

### has Str $.empty-message

Message rendered when there are no points. The default is the expected startup state for monitoring dashboards. Set to the empty string to suppress.

### method braille-glyph

```raku
method braille-glyph(
    Int $bits where { ... }
) returns Str
```

Compute the braille codepoint for a given bit pattern (0..255). Pure function, exhaustively unit-testable.

### method braille-bit

```raku
method braille-bit(
    Int $sub-col where { ... },
    Int $sub-row where { ... }
) returns UInt
```

Compute the bit position within a braille cell for a sub-cell coordinate. `$sub-col` is 0 or 1; `$sub-row` is 0..3. Returns a bit index 0..7 suitable for use with `braille-glyph`.

