NAME
====

Selkie::Widget::ProgressBar - Determinate or indeterminate progress bar

SYNOPSIS
========

```raku
use Selkie::Widget::ProgressBar;
use Selkie::Sizing;

# Determinate: value 0.0 to 1.0
my $pb = Selkie::Widget::ProgressBar.new(sizing => Sizing.fixed(1));
$pb.set-value(0.42);                 # 42%

# Indeterminate: animated bouncing block
my $spinner = Selkie::Widget::ProgressBar.new(
    indeterminate    => True,
    show-percentage  => False,
    sizing           => Sizing.fixed(1),
);
$app.on-frame: { $spinner.tick };    # advance animation each frame
```

DESCRIPTION
===========

A horizontal bar showing progress. Two modes:

  * **Determinate** — `value` 0.0–1.0 fills the bar left to right. Shows percentage unless disabled.

  * **Indeterminate** — a small block bounces left-right inside the bar. Animation advances by one step every `frames-per-step` calls to `tick`. No percentage shown.

Non-focusable by default (it's a display widget).

EXAMPLES
========

Job progress driven by the store
--------------------------------

```raku
$app.store.subscribe-with-callback(
    'progress',
    -> $s {
        my $done  = $s.get-in('job', 'step')  // 0;
        my $total = $s.get-in('job', 'total') // 1;
        $total == 0 ?? 0.0 !! ($done / $total).Rat;
    },
    -> $frac { $pb.set-value($frac) },
    $pb,
);
```

Toggle animation based on running state
---------------------------------------

```raku
$app.store.subscribe-with-callback(
    'spinner-running',
    -> $s { $s.get-in('job', 'running') // False },
    -> Bool $running { $spinner.indeterminate = $running },
    $spinner,
);
```

### has Rat $.value

Current progress, 0.0 to 1.0. Ignored when `indeterminate` is True.

### has Bool $.show-percentage

Render a "NN%" suffix after the bar (determinate mode only).

### has Bool $.indeterminate

Switch to bouncing-block animation mode. Flip at runtime with direct assignment (it's `is rw`) — the bar updates on the next `tick`.

### has Str $.fill-char

Character used for the filled portion of the bar.

### has Str $.empty-char

Character used for the empty portion.

### has UInt $.frames-per-step

Indeterminate bounce speed: one step per N ticks. Default 4 gives a comfortable animation at 60fps.

### method value

```raku
method value() returns Rat
```

Current value, clamped 0.0..1.0.

### method set-value

```raku
method set-value(
    Rat(Cool) $v
) returns Mu
```

Set progress to a fraction 0.0..1.0. Out-of-range inputs are clamped. No-op if the value is unchanged (so it's safe to call on every frame).

### method tick

```raku
method tick() returns Mu
```

Advance the indeterminate animation by one frame. No-op in determinate mode. Call from a frame callback: $app.on-frame: { $spinner.tick };

