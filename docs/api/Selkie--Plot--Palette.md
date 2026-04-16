NAME
====

Selkie::Plot::Palette - Colorblind-friendly series palettes and color ramps for chart widgets

SYNOPSIS
========

```raku
use Selkie::Plot::Palette;

# Series palettes — discrete colors for multi-series charts
my @colors = Selkie::Plot::Palette.series('okabe-ito');
# (0xE69F00, 0x56B4E9, 0x009E73, 0xF0E442, 0x0072B2,
#  0xD55E00, 0xCC79A7, 0x999999)

# Color ramps — continuous gradients for heatmaps
my @stops = Selkie::Plot::Palette.ramp('viridis');
# (0.0 => 0x440154, 0.25 => 0x3B528B, 0.5 => 0x21908C, ...)

# Sample a ramp at any position in [0, 1]
my $color = Selkie::Plot::Palette.sample('viridis', 0.42);
# → 0x2E6A8E (interpolated between 0.25 and 0.5 stops)
```

DESCRIPTION
===========

Two abstractions for chart colors:

  * **Series palettes** — discrete lists of distinct colors for multi-series charts (BarChart with N categories, LineChart with N series). Defaults to [Okabe-Ito](https://jfly.uni-koeln.de/color/), designed to be distinguishable for the most common forms of colorblindness.

  * **Color ramps** — continuous gradients sampled by a normalised position in `[0, 1]`, for heatmaps and other value-encoded color use. Defaults to [viridis](https://bids.github.io/colormap/), the perceptually uniform colormap that's been the matplotlib default since 2.0.

Both are *separate from* [Selkie::Theme](Selkie--Theme.md). Theme slots cover named chart elements (axis, gridlines, legend background); palettes cover data colors. Different access patterns, different homes.

Series palettes
---------------

  * `okabe-ito` (default, 8 colors) — Okabe & Ito's palette, optimised for deuteranopia / protanopia / tritanopia. The original palette starts with pure black, which is invisible on dark backgrounds; this implementation substitutes `0x999999` as the first color so the palette works on either light or dark themes.

  * `tol-bright` (7 colors) — Paul Tol's "bright" qualitative palette ([personal.sron.nl/~pault](https://personal.sron.nl/~pault/)). Higher saturation, also colorblind-safe.

  * `tableau-10` (10 colors) — Tableau's category10 palette. Vivid and well-tested in business dashboards. Less colorblind-friendly than Okabe-Ito but maximises distinct hues for many series.

If a chart needs more series than its palette provides, the colors cycle. For more than ~8 series consider redesigning the chart (faceting, stacked layout, on-hover series isolation) — at a glance, the human eye can't reliably distinguish more than ~7 chart series by color alone.

Color ramps
-----------

All ramps are 5-stop. Sampling between stops uses straight linear interpolation in RGB space — perceptually correct interpolation would need OkLab or Lab conversion, which is overkill for terminal cells where adjacent values blur visually anyway.

  * `viridis` (default for heatmaps) — perceptually uniform, colorblind-safe, prints reasonably in greyscale. The matplotlib default since 2.0.

  * `magma` — like viridis but warmer (purple → red → cream).

  * `plasma` — high-saturation gradient (deep blue → pink → orange).

  * `coolwarm` — diverging blue→white→red, useful for signed data where 0 is special (correlations, deltas).

  * `grayscale` — five steps of gray. Mostly for accessibility fallback or print contexts.

EXAMPLES
========

Coloring a multi-series LineChart
---------------------------------

```raku
my @palette = Selkie::Plot::Palette.series('okabe-ito');
my @series = (
    { label => 'cpu',     values => @cpu,    color => @palette[0] },
    { label => 'memory',  values => @mem,    color => @palette[1] },
    { label => 'iowait',  values => @iowait, color => @palette[2] },
);

my $chart = Selkie::Widget::LineChart.new(:@series, :show-legend);
```

Driving a Heatmap with a custom ramp stop
-----------------------------------------

```raku
my $heatmap = Selkie::Widget::Heatmap.new(
    data => @grid,
    ramp => 'coolwarm',
);

# Or, for one-off color lookups in custom widget code:
my $color = Selkie::Plot::Palette.sample('viridis', $normalised-value);
```

Cycling a palette beyond its length
-----------------------------------

```raku
my @palette = Selkie::Plot::Palette.series('tol-bright');   # 7 colors
my $color-for = sub ($i) { @palette[$i mod @palette.elems] };

# Series 0..6 get distinct colors; 7 wraps to series 0's color.
```

SEE ALSO
========

  * [Selkie::Plot::Scaler](Selkie--Plot--Scaler.md) — value→cell mapping

  * [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md) — nice-number axis labels

  * [Selkie::Theme](Selkie--Theme.md) — chart-element styling slots (axis, legend bg, etc.)

### method series

```raku
method series(
    Str:D $name = "okabe-ito"
) returns List
```

Return the named series palette as a list of 24-bit RGB integers. Defaults to `okabe-ito`. Throws on unknown names.

### method ramp

```raku
method ramp(
    Str:D $name = "viridis"
) returns List
```

Return the named color ramp as a list of `Real =` UInt> Pairs, each pair being a position in `[0, 1]` mapped to a 24-bit RGB. Defaults to `viridis`. Throws on unknown names.

### method sample

```raku
method sample(
    Str:D $name,
    Real $t
) returns UInt
```

Sample a ramp at `$t ∈ [0, 1]`, returning the interpolated 24-bit RGB color. Out-of-range `$t` is clamped. Interpolation is linear in RGB space (not OkLab) — adequate for terminal cells.

