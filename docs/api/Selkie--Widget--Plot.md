NAME
====

Selkie::Widget::Plot - Streaming chart wrapping notcurses' native ncuplot/ncdplot

SYNOPSIS
========

```raku
use Selkie::Widget::Plot;
use Selkie::Sizing;

# Streaming uint plot — push samples as they arrive
my $cpu = Selkie::Widget::Plot.new(
    type     => 'uint',
    min-y    => 0,
    max-y    => 100,
    title    => 'CPU %',
    sizing   => Sizing.flex,
);

$cpu-supply.tap: -> $sample-pct {
    state $tick = 0;
    $cpu.push-sample($tick++, $sample-pct);
};

# Streaming double plot for fractional / non-integer measurements
my $temp = Selkie::Widget::Plot.new(
    type    => 'double',
    min-y   => -10.0,
    max-y   => 40.0,
    sizing  => Sizing.flex,
);

# Reactive — bind to a store array of (x, y) pairs and the widget
# will pick up new samples from store updates.
my $bound = Selkie::Widget::Plot.new(
    store-path => <metrics throughput>,
    type       => 'uint',
    min-y      => 0,
    max-y      => 1000,
    sizing     => Sizing.flex,
);
```

DESCRIPTION
===========

`Selkie::Widget::Plot` wraps notcurses' built-in plot widgets: `ncuplot` (uint64 samples) and `ncdplot` (num64 samples). The native code handles scaling, tick marks, blitter selection, and incremental rendering — this widget's job is lifecycle management (creating and destroying the native handle, surviving plane resizes), the Selkie sample-push API, and optional store binding.

The plot is **streaming-oriented**: you push samples one at a time and it maintains a ring buffer of recent samples internally. For fixed/static data plotted with full chart machinery (axes, legends, multi-series), use [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) instead. For an inline single-row chart, use [Selkie::Widget::Sparkline](Selkie--Widget--Sparkline.md).

The two type variants
---------------------

  * **uint** (default) — wraps `ncuplot_*`. Y values are `uint64`. Pass `:type<uint>`.

  * **double** — wraps `ncdplot_*`. Y values are `num64`. Pass `:type<double>` for fractional measurements.

X values are always `uint64` in both variants — they're slot indices, not arbitrary numeric values. If you need a non-monotonic or floating-point x-axis, use [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) or [Selkie::Widget::ScatterPlot](Selkie--Widget--ScatterPlot.md).

Native handle lifecycle
-----------------------

The native ncuplot / ncdplot handle is created lazily on the first `render()` after the widget gets a plane. It survives until one of:

  * **resize** — the handle is destroyed and a new one is created at the new dimensions. **Existing samples are lost.** notcurses' plot API exposes no way to transfer sample state across resize. If you need history that survives terminal resize, keep the sample buffer outside the widget (e.g. in the store) and use [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) with reactive binding instead.

  * **park** — when scrolled off-screen by a container swap, the handle is destroyed proactively. Recreated on the next render.

  * **destroy** — final cleanup at widget shutdown.

Samples pushed before the handle exists (e.g. between widget construction and first plane attach) are buffered and flushed to the handle when it's created.

Reactive binding
----------------

`:store-path` binds the widget to a store path holding a list of `($x, $y)` pairs. On dirty (when the store updates), the widget diffs the new list against its last-pushed-index and forwards new samples to the native handle. Truncating the array (or replacing it with a shorter one) causes the widget to recreate the handle and re-push from scratch.

EXAMPLES
========

Plotting an interval-driven sine wave
-------------------------------------

```raku
use Selkie::Widget::Plot;

my $plot = Selkie::Widget::Plot.new(
    type   => 'double',
    min-y  => -1.0,
    max-y  => 1.0,
    sizing => Sizing.flex,
);

# Drive samples from an interval Supply
react {
    whenever Supply.interval(0.05) -> $i {
        my $value = sin($i * 0.1);
        $plot.push-sample($i, $value);
    }
}
```

Lifecycle and resize behavior
-----------------------------

The handle automatically recreates on resize. Sample history is lost, which is fine for a streaming dashboard but might surprise you in testing:

```raku
my $plot = Selkie::Widget::Plot.new(:type<uint>, :min-y(0), :max-y(100));
$plot.push-sample(0, 50);
$plot.push-sample(1, 75);

# Simulate a terminal resize:
$plot.handle-resize(20, 80);

# At this point the previous samples are gone — the handle was
# recreated at the new dimensions. To preserve history, keep the
# sample buffer in your app code (or the store) and re-push after
# resize. For a chart that survives resize without manual
# bookkeeping, use Selkie::Widget::LineChart instead.
```

Disabling spesh in test code
----------------------------

The shared notcurses + native plot interaction trips the MoarVM specializer in some pathological cases. The snapshot harness sets `MVM_SPESH_DISABLE=1` globally; in your own test code that exercises the Plot widget's lifecycle, set the env var before running. See `xt/snapshots/25-plot-streaming.raku` for a working example.

SEE ALSO
========

  * [Selkie::Widget::Sparkline](Selkie--Widget--Sparkline.md) — single-row inline chart, no native handle

  * [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) — full multi-series chart for static data

  * [Selkie::Plot::Scaler](Selkie--Plot--Scaler.md)

### has Str $.type

Sample type variant: `uint` (default) wraps `ncuplot`, `double` wraps `ncdplot`.

### has Real $.min-y

Lower bound of the Y range. Below this, samples saturate to the bottom of the plot.

### has Real $.max-y

Upper bound of the Y range. Above this, samples saturate to the top of the plot.

### has Str $.title

Optional title written above the plot by notcurses.

### has Int $.gridtype

Notcurses blitter for the plot rendering. Defaults to braille (2×4 sub-cell resolution); see `NCBLIT_*` in `Notcurses::Native::Types`.

### has UInt $.rangex

Number of x-axis slots in the ring buffer. Defaults to widget width × 2 so braille's sub-cell density is fully used. Set explicitly when pushing more than one sample per cell-column.

### has Positional[Str] @.store-path

Optional reactive binding — store path to a list of `($x, $y)` pairs. The widget pushes new samples to the native handle when the store path updates.

### has Str $.empty-message

Message rendered when no samples have been received yet. The default is the expected startup state for monitoring dashboards. Set to the empty string to suppress (the plot will show a blank pane until the first sample arrives).

### method push-sample

```raku
method push-sample(
    Int(Cool) $x,
    Real $y
) returns Mu
```

Push a sample. `$x` is the slot index (always integer); `$y` is the value (UInt for type=uint, Num for type=double). If the native handle doesn't exist yet (before plane attach or immediately after resize), the sample is buffered and flushed on next render.

### method set-sample

```raku
method set-sample(
    Int(Cool) $x,
    Real $y
) returns Mu
```

Set (overwrite) the sample at slot `$x`. Same semantics as notcurses' `ncuplot_set_sample` / `ncdplot_set_sample`: replaces rather than accumulating. No-op if the handle hasn't been created yet — use `push-sample` for buffer-aware writes.

### method has-handle

```raku
method has-handle() returns Bool
```

Returns True iff the native plot handle is currently allocated. Mostly useful in tests verifying lifecycle behavior.

