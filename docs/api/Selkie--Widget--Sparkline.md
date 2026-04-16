NAME
====

Selkie::Widget::Sparkline - Inline single-row chart using Unicode block glyphs

SYNOPSIS
========

```raku
use Selkie::Widget::Sparkline;
use Selkie::Sizing;

# Static data — fixed series
my $sl = Selkie::Widget::Sparkline.new(
    data   => [1, 4, 2, 8, 5, 9, 3, 7],
    sizing => Sizing.fixed(1),
);

# Streaming — push samples as they arrive
my $stream = Selkie::Widget::Sparkline.new(sizing => Sizing.fixed(1));
$cpu-supply.tap: -> $sample { $stream.push-sample($sample) };

# Reactive — read from a store path that holds the array
my $bound = Selkie::Widget::Sparkline.new(
    store-path => <metrics latency-history>,
    sizing     => Sizing.fixed(1),
);
```

DESCRIPTION
===========

A single-row inline chart that maps numeric values to the Unicode "lower one-eighth block" series:

    ▁ ▂ ▃ ▄ ▅ ▆ ▇ █

Each cell shows one sample. The widget's width determines how many samples are visible — when the buffer overflows, the oldest sample is discarded (FIFO ring buffer).

Sparklines are designed to live inline with text or in table cells, not as standalone visualisations. For a full-fledged line chart with axes and legends, use [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) (static data) or [Selkie::Widget::Plot](Selkie--Widget--Plot.md) (streaming).

Construction modes
------------------

  * **Static** — pass `:data(@arr)` for a fixed sample series. The widget renders the same data every frame.

  * **Streaming** — construct without `:data`, then call `.push-sample($v)` as new samples arrive. Internal ring buffer caps at the widget's column count.

  * **Reactive** — pass `:store-path<a b c>` to read the sample array from a store path on each render. Subscription marks the widget dirty when the value changes.

The three modes are mutually exclusive: pass exactly one of `:data` or `:store-path`, or neither (streaming). Mixing throws at TWEAK.

Value mapping
-------------

Values are mapped linearly from `[min, max]` (auto-derived from the buffer) onto the eight glyph levels. By default `min` is the minimum sample seen and `max` the maximum; pass explicit `:min` / `:max` to fix the range across renders (useful when streaming so the heights don't jitter as new samples shift the auto-range).

`NaN` samples render as a space (the cell is skipped). Negative or positive infinities clamp to the corresponding edge glyph.

EXAMPLES
========

Inline in a status bar
----------------------

```raku
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::Sparkline;
use Selkie::Sizing;

my $status = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$status.add: Selkie::Widget::Text.new(text => 'CPU: ', sizing => Sizing.fixed(5));
$status.add: $cpu-sparkline,                         sizing => Sizing.fixed(20);
$status.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);
```

In a Table cell
---------------

Embed sparklines in a table column to show per-row history. The hand-rolled implementation has no native handle, so it's cheap to instantiate one per row:

```raku
use Selkie::Widget::Table;

my $table = Selkie::Widget::Table.new(...);
$table.add-column(
    name     => 'history',
    width    => 20,
    renderer => -> %row {
        Selkie::Widget::Sparkline.new(
            data   => %row<latency-samples>,
            sizing => Sizing.fixed(1),
        );
    },
);
```

Streaming with a fixed range
----------------------------

Auto-range jitter is annoying when you want to see absolute trends. Pin the range to your domain knowledge:

```raku
my $cpu-spark = Selkie::Widget::Sparkline.new(
    min    => 0,           # CPU is 0..100%
    max    => 100,
    sizing => Sizing.fixed(1),
);
$cpu-supply.tap: -> $sample { $cpu-spark.push-sample($sample) };
```

SEE ALSO
========

  * [Selkie::Widget::LineChart](Selkie--Widget--LineChart.md) — full chart with axes, legends, multi-series

  * [Selkie::Widget::Plot](Selkie--Widget--Plot.md) — streaming chart with native ncuplot ring buffer

  * [Selkie::Plot::Scaler](Selkie--Plot--Scaler.md) — the value→cell mapping primitive

### has Positional[Real] @.data

Static sample list. Mutually exclusive with `store-path`.

### has Positional[Str] @.store-path

Reactive store path — list-of-strings forming the lookup. Mutually exclusive with `data`.

### has Real $.min

Optional fixed range lower bound. When unset, the minimum across the current buffer is used (auto-range).

### has Real $.max

Optional fixed range upper bound. See `min`.

### has Str $.empty-message

Message rendered when there are no samples yet. This is the expected startup state for monitoring dashboards, so defaults to a calm placeholder rather than nothing. Disable by setting to the empty string.

### method push-sample

```raku
method push-sample(
    Real $v
) returns Mu
```

Append a single sample to the streaming ring buffer. When the buffer reaches the widget's column count, the oldest sample is discarded. No-op in `:data` or `:store-path` mode (the buffer is owned by the data source, not the widget).

### method set-data

```raku
method set-data(
    @new
) returns Mu
```

Replace the static data array. Only valid in `:data` mode.

