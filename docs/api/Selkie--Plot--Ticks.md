NAME
====

Selkie::Plot::Ticks - Heckbert "nice-number" tick generation for axes

SYNOPSIS
========

```raku
use Selkie::Plot::Ticks;

# Roughly five ticks across [0, 100]. Heckbert lands on step=20 (the
# nearest "nice" multiplier in {1, 2, 5}); five ticks would have
# wanted step=25, which isn't in the set, so we get six instead.
my $t = Selkie::Plot::Ticks.nice(min => 0, max => 100, count => 5);
$t.values;     # → (0, 20, 40, 60, 80, 100)
$t.labels;     # → ("0", "20", "40", "60", "80", "100")
$t.step;       # → 20

# Awkward endpoints — Heckbert pads to nice numbers
my $u = Selkie::Plot::Ticks.nice(min => 7, max => 93, count => 5);
$u.values;     # → (0, 20, 40, 60, 80, 100)  — extends past min/max
$u.step;       # → 20

# Sub-unit ranges produce sub-unit steps
my $v = Selkie::Plot::Ticks.nice(min => 0, max => 1, count => 5);
$v.values;     # → (0, 0.2, 0.4, 0.6, 0.8, 1.0)
$v.labels;     # → ("0.0", "0.2", "0.4", "0.6", "0.8", "1.0")
$v.step;       # → 0.2
```

DESCRIPTION
===========

`Selkie::Plot::Ticks` picks "nice" tick values for an axis covering the domain `[min, max]`. Nice means each tick is a multiple of `step`, and `step` is chosen from `{1, 2, 5} × 10^n` for some integer `n` — the values that humans naturally read on a graph.

The algorithm is Paul Heckbert's classic, described in *Graphics Gems* (1990): pick a "nice" range, divide it into roughly `count` intervals, snap the interval to a nice number, then enumerate ticks. The output count is *approximately* `count`, not exactly — typical deviation is ±1 tick.

The algorithm
-------------

Given `min`, `max`, and a target `count`:

  * Compute `range = max - min` and snap it up to a nice number (floored to a 1, 2, 5, or 10 leading digit).

  * Compute `rough-step = range / (count - 1)` and snap it *rounded* to a nice number — small differences in `rough-step` shouldn't bump the leading digit if either side is reasonable.

  * Compute `nice-min = floor(min / step) * step` and `nice-max = ceil(max / step) * step` — round the data range outward to the nearest tick.

  * Enumerate ticks at `nice-min, nice-min + step, nice-min + 2·step, ..., nice-max`.

The result is a tick set whose endpoints *may extend slightly beyond* the data range. This is intentional — chart axes look better when the labels are round numbers like `0` and `100` rather than the precise data extent of `7` and `93`.

A worked example
----------------

For `min = 0.001`, `max = 0.009`, `count = 4`:

  * `range = nice(0.008, :!round)`. `0.008 / 10^-3 = 8` → leading digit 10 → range = `0.01`.

  * `rough-step = 0.01 / 3 ≈ 0.00333`. `nice(0.00333, :round)`: `3.33 / 10^-3 = 3.33` → leading digit 5 → step = `0.005`.

  * `nice-min = floor(0.001 / 0.005) * 0.005 = 0`. `nice-max = ceil(0.009 / 0.005) * 0.005 = 0.01`.

  * Ticks: `0, 0.005, 0.01` — three ticks, requested four. Heckbert prefers nice spacing over exact count.

Edge cases
----------

  * **`count E<lt> 2`** — nonsensical (a single tick has no spacing). Throws.

  * **`min E<gt> max`** — throws. Pass arguments in order.

  * **`min == max`** — degenerate. Returns a single-element tick set at `min`; `step` is `0`.

EXAMPLES
========

Driving an axis widget
----------------------

```raku
use Selkie::Plot::Scaler;
use Selkie::Plot::Ticks;
use Selkie::Widget::Axis;

my $scaler = Selkie::Plot::Scaler.linear(min => 0, max => 1000, cells => 80);
my $ticks  = Selkie::Plot::Ticks.nice(min => 0, max => 1000, count => 5);

my $axis = Selkie::Widget::Axis.new(
    edge   => 'bottom',
    :$scaler,
    :$ticks,
);
```

Picking labels for a sub-unit range
-----------------------------------

When the step is fractional, labels are zero-padded to the step's precision so they align visually:

```raku
my $t = Selkie::Plot::Ticks.nice(min => 0.0, max => 0.1, count => 5);
$t.step;       # → 0.02
$t.labels;     # → ("0.00", "0.02", "0.04", "0.06", "0.08", "0.10")
```

SEE ALSO
========

  * [Selkie::Plot::Scaler](Selkie--Plot--Scaler.md) — maps tick values to cell positions

  * [Selkie::Widget::Axis](Selkie--Widget--Axis.md) — renders ticks + labels along an edge

### has Real $.min

The data-range lower bound passed in.

### has Real $.max

The data-range upper bound passed in.

### has UInt $.count

The target tick count (approximate; actual may differ by ±1-2).

### has Real $.step

The chosen tick step. Always a member of `{1, 2, 5} × 10^n`. Zero in the degenerate `min == max` case.

### has Positional[Real] @.values

The generated tick values, in ascending order.

### method nice

```raku
method nice(
    Real :$min!,
    Real :$max!,
    Int :$count where { ... } = 5
) returns Selkie::Plot::Ticks
```

Generate a nice tick set covering `[min, max]` with approximately `count` ticks. The actual count may differ from `count` by ±1-2 — Heckbert prefers round numbers over an exact count. Throws if C<count E<lt> 2> or if C<min E<gt> max>. `min == max` is permitted (returns a single-tick set).

### method values

```raku
method values() returns List
```

Return the tick values as a list. Same data as the `values` accessor; this method exists for API symmetry with `labels`.

### method labels

```raku
method labels() returns List
```

Return formatted labels for each tick. Labels use a fixed decimal precision derived from `step` so they align visually: =item Integer step (e.g. 25) → no decimals: `("0", "25", "50")` =item Sub-unit step (e.g. 0.005) → decimals matching the step: `("0.000", "0.005", "0.010")` Negative ticks render with a leading minus sign.

