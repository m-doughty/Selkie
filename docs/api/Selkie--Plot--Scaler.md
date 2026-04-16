NAME
====

Selkie::Plot::Scaler - Map a numeric domain onto a discrete cell range

SYNOPSIS
========

```raku
use Selkie::Plot::Scaler;

# A linear scaler that maps the domain [0, 100] onto a 20-cell axis.
my $s = Selkie::Plot::Scaler.linear(min => 0, max => 100, cells => 20);

$s.value-to-cell(0);     # → 0
$s.value-to-cell(50);    # → 10
$s.value-to-cell(100);   # → 19
$s.value-to-cell(150);   # → 19  (clamped)
$s.value-to-cell(-10);   # → 0   (clamped)
$s.cell-to-value(10);    # → 52.6315... (midpoint of cell 10)

# Inverted axis — cell 0 holds the maximum value, useful for y-axes
# where the top of the screen is row 0 but the largest value should
# render highest on the chart.
my $y = Selkie::Plot::Scaler.linear(
    min => 0, max => 100, cells => 20, :invert,
);
$y.value-to-cell(100);   # → 0    (top row)
$y.value-to-cell(0);     # → 19   (bottom row)
```

DESCRIPTION
===========

A `Selkie::Plot::Scaler` maps a numeric value in the domain `[min, max]` to an integer cell index in `[0, cells-1]`. It's the shared coordinate-mapping primitive used by every chart widget — `Sparkline`, `BarChart`, `LineChart`, `ScatterPlot`, `Heatmap`, and the axes that label them.

The scaler is pure data: no notcurses, no widget, no I/O. It's deterministic and exhaustively unit-testable, which matters because a miscomputed mapping silently corrupts every chart that uses it.

The linear formula
------------------

For `cells E<gt> 1`:

    cell = round( (value - min) / (max - min) * (cells - 1) )

then clamped to `[0, cells-1]`. With `:invert` the result is flipped: `cell = (cells - 1) - cell`.

The inverse `cell-to-value` returns the value at the midpoint of the target cell:

    value = (cell / (cells - 1)) * (max - min) + min

A round-trip `cell-to-value(value-to-cell(v))` recovers `v` within `± (max - min) / (2 * (cells - 1))` — the half-cell precision floor imposed by the integer cell grid.

Edge cases
----------

  * **`cells` must be > 0** — zero-cell scalers are nonsensical and throw.

  * **`min == max` degenerate range** — every value maps to the middle cell. `cell-to-value` returns `min` (which equals `max`).

  * **`min E<gt> max`** — throws. Inverted *axes* are expressed via `:invert`, not via reversed bounds.

  * **`NaN` input** — `value-to-cell` returns `UInt` (the typed undef). NaN is propagated, not clamped, so callers can detect missing samples.

  * **`+Inf` / `-Inf` input** — clamped to the corresponding edge cell (`cells - 1` for `+Inf`, `0` for `-Inf`; flipped under `:invert`).

  * **Out-of-domain value** — clamped to the nearest edge cell. No exception.

EXAMPLES
========

Composing scalers for a 2D plot
-------------------------------

A scatter plot needs two scalers — one per axis. The y-scaler is typically inverted because terminal row 0 is the *top* of the screen but charts conventionally place the maximum value *at the top*.

```raku
my $x-scaler = Selkie::Plot::Scaler.linear(
    min => 0, max => $duration, cells => $width,
);
my $y-scaler = Selkie::Plot::Scaler.linear(
    min => $min-y, max => $max-y, cells => $height, :invert,
);

for @samples -> %point {
    my $col = $x-scaler.value-to-cell(%point<t>);
    my $row = $y-scaler.value-to-cell(%point<v>);
    plot-dot($row, $col);
}
```

Recovering tick values for axis labels
--------------------------------------

When generating axis tick labels (see [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md)) you want the value at a given cell. `cell-to-value` gives the cell midpoint:

```raku
my $axis-scaler = Selkie::Plot::Scaler.linear(
    min => 0, max => 1000, cells => 80,
);
say $axis-scaler.cell-to-value(0);    # → 0
say $axis-scaler.cell-to-value(40);   # → 506.32...
say $axis-scaler.cell-to-value(79);   # → 1000
```

SEE ALSO
========

  * [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md) — generates "nice" tick values for a domain

  * [Selkie::Plot::Palette](Selkie--Plot--Palette.md) — colorblind-safe series colors and ramps

  * [Selkie::Widget::Axis](Selkie--Widget--Axis.md) — renders ticks + labels along a chart edge

### has Real $.min

Domain lower bound (inclusive).

### has Real $.max

Domain upper bound (inclusive).

### has UInt $.cells

Number of discrete cells in the target range. Must be > 0.

### has Bool $.invert

Whether to flip the mapping (cell 0 holds the maximum value).

### method linear

```raku
method linear(
    Real :$min!,
    Real :$max!,
    Int :$cells! where { ... },
    Bool :$invert = Bool::False
) returns Selkie::Plot::Scaler
```

Linear scaler constructor. Throws if `cells` is 0 or if C<min E<gt> max>. `min == max` is permitted (degenerate range — every value maps to the middle cell). Use `:invert` for axes where cell 0 should hold the maximum value (typically y-axes — terminal row 0 is the top of the screen, and charts conventionally render the largest value highest).

### method value-to-cell

```raku
method value-to-cell(
    Real $value
) returns UInt
```

Map a value in the domain to a cell index in `[0, cells-1]`. Out-of-domain values are clamped to the nearest edge. `NaN` propagates as `UInt` (the typed undef). `±Inf` clamps to the corresponding edge.

### method cell-to-value

```raku
method cell-to-value(
    Int $cell-in
) returns Real
```

Map a cell index back to its midpoint value in the domain. Out-of-range cell indices are clamped.

