NAME
====

Selkie::Widget::Histogram - Bin a numeric series and render it as a BarChart

SYNOPSIS
========

```raku
use Selkie::Widget::Histogram;
use Selkie::Sizing;

# Bin 1000 random samples into 10 bins
my @samples = (1..1000).map: { rand * 100 };
my $h = Selkie::Widget::Histogram.new(
    values => @samples,
    bins   => 10,
    sizing => Sizing.flex,
);

# Custom bin edges instead of equal-width bins
my $edges = Selkie::Widget::Histogram.new(
    values    => @latencies-ms,
    bin-edges => [0, 10, 50, 100, 500, 1000, 5000],
    sizing    => Sizing.flex,
);
```

DESCRIPTION
===========

A histogram is a categorical view of a numeric distribution. This widget bins a list of numeric values into intervals and delegates rendering to [Selkie::Widget::BarChart](Selkie--Widget--BarChart.md). Each bin becomes a bar labelled by its lower edge.

Bin convention
--------------

Intervals are **left-closed, right-open**, with the final bin **closed-closed** so the maximum sample is always counted. For bin edges `[0, 10, 20, 30]`:

  * Bin 1: `[0, 10)` — values 0 ≤ v < 10

  * Bin 2: `[10, 20)`

  * Bin 3: `[20, 30]` — values 20 ≤ v ≤ 30 (inclusive)

This matches numpy / R / matplotlib defaults.

Modes
-----

Two ways to specify the bins:

  * **Equal-width** — pass `:bins(N)`. The widget computes N equal-width bins spanning `[min, max]` of the data.

  * **Explicit edges** — pass `:bin-edges([...])`. The widget uses your edges directly. `edges.elems` = bin count + 1.

The two are mutually exclusive. `:bins` is convenient; `:bin-edges` is for non-uniform binning (log-scale latency, age brackets, etc.).

EXAMPLES
========

Distribution of request latencies
---------------------------------

```raku
my @latencies = $request-log.map: *.<duration-ms>;
my $h = Selkie::Widget::Histogram.new(
    values => @latencies,
    bins   => 20,
    sizing => Sizing.flex,
);
```

Non-uniform bins for skewed data
--------------------------------

Latencies cluster near zero with a long tail. Equal bins waste most of the chart on near-zero values. Custom edges let you focus on the distribution where it matters:

```raku
my $h = Selkie::Widget::Histogram.new(
    values    => @latencies,
    bin-edges => [0, 5, 10, 25, 50, 100, 250, 500, 1000, 5000],
    sizing    => Sizing.flex,
);
```

Reactive — auto-rebin when the source data changes
--------------------------------------------------

```raku
# Histogram doesn't bind to a store directly; instead, subscribe in
# app code and call set-values when the source updates.
$store.subscribe-with-callback(
    'latencies-hist',
    -> $s { $s.get-in('metrics', 'latency-samples') // [] },
    -> @samples { $hist.set-values(@samples) },
    $hist,
);
```

SEE ALSO
========

  * [Selkie::Widget::BarChart](Selkie--Widget--BarChart.md) — the bar renderer this delegates to

  * [Selkie::Plot::Ticks](Selkie--Plot--Ticks.md) — for picking nice bin edges manually

### has Positional[Real] @.values

Numeric values to bin.

### has UInt $.bins

Equal-width bin count. Mutually exclusive with `bin-edges`.

### has Positional[Real] @.bin-edges

Explicit bin edges, ascending. `bin-edges.elems` = bin count + 1. Mutually exclusive with `bins`.

### method set-values

```raku
method set-values(
    @new
) returns Mu
```

Replace the value list and re-bin. The chart re-renders automatically.

