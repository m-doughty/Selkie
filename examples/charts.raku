#!/usr/bin/env raku
#
# charts.raku — Showcase of all seven Selkie chart widgets.
#
# Demonstrates, from top to bottom:
#   - Sparkline bound reactively to a store path; the widget
#     re-renders automatically when the path's value changes.
#   - LineChart updated from a store subscription (the widget
#     accepts static :series, so we call set-series from the
#     subscription callback).
#   - BarChart + Histogram + Heatmap: three kinds of categorical
#     / distribution views side-by-side. Static for this demo.
#   - Plot + ScatterPlot: streaming native plot next to a braille
#     scatter.
#
# The reactive pattern: every few frames we dispatch `metrics/tick`,
# which shifts the sample buffers in the store. Subscribers
# (Sparkline, LineChart) re-render off the new values — no
# imperative .set-anything calls from the frame callback.
#
# Run with:  raku -I lib examples/charts.raku
# Quit with: Ctrl+Q

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::Border;
use Selkie::Sizing;
use Selkie::Style;

use Selkie::Widget::Sparkline;
use Selkie::Widget::Plot;
use Selkie::Widget::BarChart;
use Selkie::Widget::Histogram;
use Selkie::Widget::Heatmap;
use Selkie::Widget::ScatterPlot;
use Selkie::Widget::LineChart;

my $app = Selkie::App.new;

# --- Store handlers --------------------------------------------------------
#
# Three rolling sample buffers (60 cells each) — live load %, p50
# latency, p99 latency. Each tick shifts the oldest sample off and
# appends a new one. This is exactly the pattern a monitoring app
# uses: the store owns the data, the widgets just render what's
# there.

constant WINDOW-SIZE = 60;

sub seed-samples(&fn --> List) {
    (^WINDOW-SIZE).map({ fn($_) }).list;
}

$app.store.register-handler('metrics/init', -> $st, %ev {
    # Same p50/p99 shape as the tick handler so the visual
    # invariant (p99 >= p50) holds from frame 0.
    my @p50 = (^WINDOW-SIZE).map({ (sin($_ * 0.2 + 1) * 20 + 30).Int });
    my @p99 = (^WINDOW-SIZE).map({
        my $gap = (cos($_ * 0.11) * 15 + 25).Int.abs;
        (@p50[$_] + $gap) min 95;
    });
    (db => {
        tick => 0,
        load => seed-samples(-> $i { (sin($i * 0.3) * 30 + 50).Int }),
        p50  => @p50,
        p99  => @p99,
    },);
});

$app.store.register-handler('metrics/tick', -> $st, %ev {
    my $t = ($st.get-in('tick') // 0) + 1;

    # Synthetic live samples. p99 must stay at or above p50 by
    # definition (99th percentile can never be below the median),
    # so we derive p99 as p50 + a non-negative gap rather than
    # generating them independently.
    my $load = (sin($t * 0.3) * 30 + 50).Int;
    my $p50  = (sin($t * 0.2 + 1) * 20 + 30).Int;        # 10..50
    my $gap  = (cos($t * 0.11) * 15 + 25).Int.abs;       # 10..40
    my $p99  = ($p50 + $gap) min 95;                     # clamp to y-axis

    sub shift-append(@buf, Int $v --> List) {
        (|@buf.tail(WINDOW-SIZE - 1), $v).list;
    }

    (db => {
        tick => $t,
        load => shift-append($st.get-in('load') // [], $load),
        p50  => shift-append($st.get-in('p50')  // [], $p50),
        p99  => shift-append($st.get-in('p99')  // [], $p99),
    },);
});

# --- Layout scaffolding ----------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

$root.add: Selkie::Widget::Text.new(
    text   => '  Selkie charts showcase  —  Ctrl+Q quits',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Row 1 — Sparkline bound to the 'load' store path. The widget
# subscribes to the path itself via on-store-attached, so we just
# hand it the path and it re-renders when the value changes.
#
# Note: .map: { ... } colon-call form swallows trailing named args
# (Raku parses `bins => 12` as a .map argument, not a constructor
# one). We use explicit parens on every .map in constructor arg
# lists below for that reason.
my $sparkline = Selkie::Widget::Sparkline.new(
    store-path => <load>,
    min        => 0,
    max        => 100,
    sizing     => Sizing.flex,
);
my $spark-row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$spark-row.add: Selkie::Widget::Text.new(
    text   => 'load: ',
    sizing => Sizing.fixed(6),
    style  => Selkie::Style.new(fg => 0x808080),
);
$spark-row.add: $sparkline;
$root.add($spark-row);

# Row 2 — LineChart. Static :series mode; we update via set-series
# from a store subscription callback. This matches the idiom used
# in examples/dashboard.raku — works without LineChart needing to
# know what store paths to subscribe to.
my $line-chart = Selkie::Widget::LineChart.new(
    series => [
        { label => 'p50', values => [], color => 0x4477AA },
        { label => 'p99', values => [], color => 0xEE6677 },
    ],
    y-min      => 0,
    y-max      => 100,
    fill-below => False,
    sizing     => Sizing.flex,
);
my $line-border = Selkie::Widget::Border.new(
    title  => 'LineChart — latency percentiles (live)',
    sizing => Sizing.flex,
);
$line-border.set-content($line-chart);
$root.add($line-border);

# Row 3 — BarChart | Histogram | Heatmap (all static)
my $mid-row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(14));

my $bar-chart = Selkie::Widget::BarChart.new(
    data => [
        { label => 'Q1', value =>  50 },
        { label => 'Q2', value =>  80 },
        { label => 'Q3', value =>  65 },
        { label => 'Q4', value => 100 },
    ],
    sizing => Sizing.flex,
);
my $bar-border = Selkie::Widget::Border.new(
    title  => 'BarChart — quarterly sales',
    sizing => Sizing.flex,
);
$bar-border.set-content($bar-chart);
$mid-row.add($bar-border);

my $histogram = Selkie::Widget::Histogram.new(
    values => (^1000).map({ 5 + 5 * sqrt(-2 * log(rand)) * cos(2 * pi * rand) }),
    bins   => 12,
    sizing => Sizing.flex,
);
my $hist-border = Selkie::Widget::Border.new(
    title  => 'Histogram — gaussian samples',
    sizing => Sizing.flex,
);
$hist-border.set-content($histogram);
$mid-row.add($hist-border);

# 8x16 heatmap of sin(r)+cos(c)
my @heatmap-data = (^8).map(-> $r {
    (^16).map(-> $c {
        sin($r * 0.5) + cos($c * 0.4);
    });
});
my $heatmap = Selkie::Widget::Heatmap.new(
    data   => @heatmap-data,
    ramp   => 'viridis',
    sizing => Sizing.flex,
);
my $heat-border = Selkie::Widget::Border.new(
    title  => 'Heatmap — sin(r) + cos(c)',
    sizing => Sizing.flex,
);
$heat-border.set-content($heatmap);
$mid-row.add($heat-border);

$root.add($mid-row);

# Row 4 — Plot | ScatterPlot
my $bot-row = Selkie::Layout::HBox.new(sizing => Sizing.flex);

my $plot = Selkie::Widget::Plot.new(
    type   => 'uint',
    min-y  => 0,
    max-y  => 100,
    title  => 'cpu%',
    sizing => Sizing.flex,
);
my $plot-border = Selkie::Widget::Border.new(
    title  => 'Plot — streaming ncuplot',
    sizing => Sizing.flex,
);
$plot-border.set-content($plot);
$bot-row.add($plot-border);

my @scatter-points;
for ^200 {
    # Two clusters: one around (25, 25), one around (75, 75)
    my $cluster = rand < 0.5;
    my $cx = $cluster ?? 25 !! 75;
    my $cy = $cluster ?? 25 !! 75;
    my $x = $cx + (rand * 20 - 10);
    my $y = $cy + (rand * 20 - 10);
    @scatter-points.push: $x => $y;
}
my $scatter = Selkie::Widget::ScatterPlot.new(
    series => [{ label => 'clusters', points => @scatter-points }],
    x-min  => 0, x-max => 100,
    y-min  => 0, y-max => 100,
    sizing => Sizing.flex,
);
my $scatter-border = Selkie::Widget::Border.new(
    title  => 'ScatterPlot — two clusters',
    sizing => Sizing.flex,
);
$scatter-border.set-content($scatter);
$bot-row.add($scatter-border);

$root.add($bot-row);

# --- Subscriptions ---------------------------------------------------------

# LineChart: rebuild its series from the two latency paths on every
# store change. The callback fires whenever either path's value
# differs from last time, which causes the widget to mark-dirty and
# re-render on the next frame.
$app.store.subscribe-with-callback(
    'latency-series',
    -> $s {
        [
            $s.get-in('p50') // [],
            $s.get-in('p99') // [],
        ]
    },
    -> @paths {
        $line-chart.set-series([
            { label => 'p50', values => @paths[0], color => 0x4477AA },
            { label => 'p99', values => @paths[1], color => 0xEE6677 },
        ]);
    },
    $line-chart,
);

# --- Frame loop -----------------------------------------------------------
# Every 4 frames (~15Hz at 60fps):
#   - dispatch metrics/tick, which the store handler uses to shift
#     the load/p50/p99 buffers. Sparkline auto-subscribes to the
#     load path and re-renders; LineChart is rewired by the
#     subscribe-with-callback above.
#   - push one sample onto the native Plot (independent of the
#     store — Plot has its own native buffer).

my UInt $frame = 0;
$app.on-frame: {
    $frame++;
    if $frame %% 4 {
        $app.store.dispatch('metrics/tick');

        my $x = $frame div 4;
        my $y = (sin($x * 0.15) * 40 + 50).Int;
        $plot.push-sample($x, $y);
    }
};

# --- Keybinds --------------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });

# --- Boot ------------------------------------------------------------------

$app.store.dispatch('metrics/init');
$app.store.tick;

$app.run;
