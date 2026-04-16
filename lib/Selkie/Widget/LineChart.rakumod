=begin pod

=head1 NAME

Selkie::Widget::LineChart - Static multi-series line chart with axes and legend

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::LineChart;
use Selkie::Sizing;

# Single series — auto-derives Y range from the data
my $cpu = Selkie::Widget::LineChart.new(
    series => [
        { label => 'cpu %', values => @cpu-history },
    ],
    sizing => Sizing.flex,
);

# Multi-series with explicit colours
my $cmp = Selkie::Widget::LineChart.new(
    series => [
        { label => 'p50', values => @p50, color => 0xE69F00 },
        { label => 'p99', values => @p99, color => 0xCC4444 },
    ],
    fill-below => True,
    sizing     => Sizing.flex,
);

=end code

=head1 DESCRIPTION

A static-data line chart, hand-rolled with braille (U+2800-U+28FF)
sub-cell resolution. Each cell holds 2×4 braille dots; lines are
rasterised at 2× horizontal × 4× vertical resolution relative to the
plain cell grid.

For B<streaming> data, prefer L<Selkie::Widget::Plot> (uses the
native ncuplot / ncdplot ring buffer; better at high sample rates).
For one-row inline charts, use L<Selkie::Widget::Sparkline>.

=head2 What it composes

Internally LineChart manages three regions:

=item B<Body> — the chart area, drawn with braille dots
=item B<Y axis> (left edge) — labels + tick marks, when C<show-axis> is True
=item B<Legend> (bottom strip) — colour-coded series labels, when C<show-legend> is True and there's more than one series

Each region renders inline via direct ncplane calls; the widget
doesn't compose child widgets. Disable axis/legend to reclaim the
reserved cells and devote all cells to the body.

=head2 Multi-series colour collision

Each braille cell renders with a single foreground colour. When two
series cross in the same 2×4 sub-cell window, the last-drawn series'
colour wins ("z-order"). Series are drawn in order; in practice this
means the last series in your list "covers" earlier ones at
intersections.

This is a fundamental limit of single-foreground terminal cells.
For series that overlap heavily, a faceted layout (one chart per
series, stacked) gives clearer attribution.

=head2 Range

Y range auto-derives from C<min(0, min-data)> to C<max-data>. Pass
explicit C<:y-min> and C<:y-max> to fix it. X is always slot indices
C<0 .. (max-series-length - 1)>; series of differing lengths are
plotted against the full domain (longer series fill the X span,
shorter series stop before the right edge).

=head2 Fill below

Pass C<:fill-below> to fill the area between each series line and
the chart's baseline (the lower edge for positive-only data). Fill
uses the C<graph-fill> theme slot when the series has no color
override; with multiple series the fill stacks visually with z-order
priority.

=head1 EXAMPLES

=head2 Single static series

=begin code :lang<raku>

my @samples = (^60).map: { sin($_ * 0.1) * 100 };
my $chart = Selkie::Widget::LineChart.new(
    series => [{ label => 'sine', values => @samples }],
    sizing => Sizing.flex,
);

=end code

=head2 Multi-series comparison

=begin code :lang<raku>

my $chart = Selkie::Widget::LineChart.new(
    series => [
        { label => 'reads',  values => @read-rate,  color => 0x4477AA },
        { label => 'writes', values => @write-rate, color => 0xEE6677 },
    ],
    sizing => Sizing.flex,
);

=end code

=head2 Fill-below for area emphasis

=begin code :lang<raku>

my $chart = Selkie::Widget::LineChart.new(
    series     => [{ label => 'load', values => @load-1m }],
    fill-below => True,
    y-min      => 0,
    y-max      => 4,
    sizing     => Sizing.flex,
);

=end code

=head2 Reactive — values bound to a store path

=begin code :lang<raku>

my $chart = Selkie::Widget::LineChart.new(
    store-path-fn => -> $store {
        [
            { label => 'series',
              values => $store.get-in('metrics', 'history') // [] },
        ]
    },
    sizing => Sizing.flex,
);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Plot> — streaming variant backed by native ncuplot
=item L<Selkie::Widget::Sparkline> — single-row inline chart
=item L<Selkie::Widget::ScatterPlot> — points without lines (also braille)
=item L<Selkie::Plot::Palette> — series colour palettes

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Plot::Scaler;
use Selkie::Plot::Ticks;
use Selkie::Plot::Palette;

unit class Selkie::Widget::LineChart does Selkie::Widget;

# Bit positions for the 8 dots in a braille cell. Same layout as
# ScatterPlot — kept duplicated for now to avoid coupling. If a third
# widget needs it, factor into a shared helper.
my @BIT-FOR = (
    [0, 1, 2, 6],   # sub-col 0 → rows 0..3
    [3, 4, 5, 7],   # sub-col 1 → rows 0..3
);

#| List of series. Each entry is a hash with C<label> (Str),
#| C<values> (Positional of Real), and optional C<color> (UInt RGB).
has @.series;

#| Optional reactive data function: C<sub ($store --> List)>. Called
#| inside C<render()> to derive series. Mutually exclusive with
#| C<series>. Useful when the data is computed from store state.
has &.store-path-fn;

#| Series-color palette name. Used when individual series don't
#| specify C<color>.
has Str $.palette = 'okabe-ito';

#| Whether to draw the Y axis. Disable to reclaim ~5 columns.
has Bool $.show-axis = True;

#| Whether to draw the legend below the chart. Auto-disabled if
#| there's only one series. Disable to reclaim 1 row.
has Bool $.show-legend = True;

#| Whether to fill the area below each line down to the baseline.
has Bool $.fill-below = False;

#| How to handle cells where multiple series have dots. Currently
#| only C<z-order> is supported (last-drawn series wins the colour).
has Str $.overlap = 'z-order';

#| Optional explicit Y bounds. Auto-derived when unset.
has Real $.y-min;
has Real $.y-max;

#| Approximate tick count for the Y axis.
has UInt $.tick-count = 5;

#| Message rendered when there are no samples. The default is the
#| expected startup state for monitoring dashboards. Set to the
#| empty string to suppress.
has Str $.empty-message = 'No data';

submethod TWEAK {
    die "Selkie::Widget::LineChart: pass at most one of :series or :store-path-fn"
        if @!series.elems > 0 && &!store-path-fn.defined;
    die "Selkie::Widget::LineChart: overlap must be 'z-order'"
        unless $!overlap eq 'z-order';

    if @!series.elems > 0 && @!series.all ~~ Pair {
        @!series = (%( |@!series ),);
    }

    # Realise each series' values once at construction. Callers often
    # build values via `(^N).map: { ... }` which yields a one-shot
    # Seq; a long-lived TUI renders the same widget every frame, so
    # without realisation the second render sees empty values.
    @!series = @!series.map(-> %s {
        my %copy = %s;
        %copy<values> = (%s<values> // ()).list.Array if %s<values>:exists;
        %copy;
    });
}

method set-series(@new) {
    die "Selkie::Widget::LineChart.set-series: only valid in :series mode"
        if &!store-path-fn.defined;
    @!series = @new.map(-> %s {
        my %copy = %s;
        %copy<values> = (%s<values> // ()).list.Array if %s<values>:exists;
        %copy;
    });
    self.mark-dirty;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);
    return self.clear-dirty if self.rows == 0 || self.cols == 0;

    my @series = self!current-series;
    my $total-samples = @series.map({ (.<values> // ()).elems }).sum;
    if @series.elems == 0 || $total-samples == 0 {
        self!render-empty;
        return self.clear-dirty;
    }

    # Allocate regions. Y axis on the left, legend on the bottom (if
    # multi-series and show-legend), body fills the rest.
    my $effective-show-legend = $!show-legend && @series.elems > 1;
    my $legend-rows = $effective-show-legend ?? 1 !! 0;
    my $axis-cols   = $!show-axis ?? self!axis-width(@series) !! 0;
    my $body-rows   = self.rows - $legend-rows;
    my $body-cols   = self.cols - $axis-cols;

    return self.clear-dirty if $body-rows <= 0 || $body-cols <= 0;

    my ($y-lo, $y-hi) = self!effective-y-range(@series);

    # Y-axis spans the whole body height.
    self!draw-y-axis($y-lo, $y-hi, $body-rows, $axis-cols) if $!show-axis;

    # Body — render each series via braille rasterisation.
    self!draw-body(@series, $axis-cols, $body-rows, $body-cols, $y-lo, $y-hi);

    # Legend — single row at the bottom.
    self!draw-legend(@series, $body-rows) if $effective-show-legend;

    self.clear-dirty;
}

method !render-empty() {
    return if $!empty-message eq '';
    self.apply-style(self.theme.text-dim);
    my $msg = $!empty-message.substr(0, self.cols);
    my $row = self.rows div 2;
    my $col = max(0, (self.cols - $msg.chars) div 2);
    ncplane_putstr_yx(self.plane, $row, $col, $msg);
}

method !current-series(--> List) {
    # Static series were realised in TWEAK; store data may still be
    # Seq-shaped, so realise on read.
    sub realise(@list --> List) {
        @list.map(-> %s {
            my %copy = %s;
            %copy<values> = (%s<values> // ()).list.Array if %s<values>:exists;
            %copy;
        }).list;
    }
    if &!store-path-fn.defined && self.store {
        my $result = &!store-path-fn(self.store);
        return $result.defined ?? realise($result.list) !! ();
    }
    @!series.list;
}

method !effective-y-range(@series --> List) {
    my @vals = @series.map({ (.<values> // ()).list }).flat
                      .grep({ .defined && $_ !=== NaN });
    my $data-min = @vals.min // 0;
    my $data-max = @vals.max // 1;
    my $lo = $!y-min // min(0, $data-min);
    my $hi = $!y-max // $data-max;
    if $lo == $hi {
        $hi = $lo + 1;
    }
    ($lo, $hi);
}

method !axis-width(@series --> UInt) {
    my ($lo, $hi) = self!effective-y-range(@series);
    my $ticks = Selkie::Plot::Ticks.nice(
        min => $lo, max => $hi, count => $!tick-count,
    );
    (($ticks.labels.map(*.chars).max // 0) + 1).UInt;
}

method !draw-y-axis(Real $lo, Real $hi, UInt $rows, UInt $axis-cols) {
    my $axis-style  = self.theme.graph-axis;
    my $label-style = self.theme.graph-axis-label;
    my $line-col    = $axis-cols - 1;

    my $scaler = Selkie::Plot::Scaler.linear(
        min => $lo, max => $hi, cells => $rows, :invert,
    );
    my $ticks = Selkie::Plot::Ticks.nice(
        min => $lo, max => $hi, count => $!tick-count,
    );

    self.apply-style($axis-style);
    for ^$rows -> $r {
        ncplane_putstr_yx(self.plane, $r, $line-col, '│');
    }
    for $ticks.values -> $v {
        my $row = $scaler.value-to-cell($v);
        next without $row.defined;
        next if $row >= $rows;
        ncplane_putstr_yx(self.plane, $row, $line-col, '┤');
    }

    self.apply-style($label-style);
    for $ticks.values.kv -> $i, $v {
        my $row = $scaler.value-to-cell($v);
        next without $row.defined;
        next if $row >= $rows;
        my $text = $ticks.labels[$i];
        my $start = max(0, $line-col - $text.chars);
        ncplane_putstr_yx(self.plane, $row, $start, $text.substr(0, $line-col));
    }
}

method !draw-body(@series, UInt $axis-cols, UInt $body-rows, UInt $body-cols,
                  Real $y-lo, Real $y-hi) {
    # Per-cell state: bit pattern + colour. Composited at the end
    # with z-order — last-drawn series wins the colour.
    my %cells;     # "$row,$col" => { bits => UInt, color => UInt }

    # Determine the X range. Use the longest series as the domain.
    my $max-len = (@series.map({ (.<values> // ()).elems }).max // 0).Int;
    return if $max-len < 1;

    # Sub-cell scalers — body extends across body-cols × 2 sub-columns
    # and body-rows × 4 sub-rows.
    my $sub-cols = $body-cols * 2;
    my $sub-rows = $body-rows * 4;

    my $x-scaler = Selkie::Plot::Scaler.linear(
        min => 0, max => max($max-len - 1, 1), cells => $sub-cols,
    );
    my $y-scaler = Selkie::Plot::Scaler.linear(
        min => $y-lo, max => $y-hi, cells => $sub-rows, :invert,
    );

    # Where is the baseline (y == 0 if in range, else the y-axis lower bound)?
    my $baseline-sub-y = ($y-lo <= 0 <= $y-hi)
        ?? $y-scaler.value-to-cell(0).Int
        !! ($sub-rows - 1);

    for @series.kv -> $i, %s {
        my $color = self!color-for($i, %s);
        my @vals  = (%s<values> // ()).list;
        next if @vals.elems < 1;

        # Convert each value to its sub-cell (x, y).
        my @points;
        for @vals.kv -> $j, $v {
            next unless $v.defined;
            next if $v === NaN;
            my $sx = $x-scaler.value-to-cell($j).Int;
            my $sy = $y-scaler.value-to-cell($v.Real).Int;
            @points.push: ($sx, $sy);
        }
        next if @points.elems < 1;

        # Optional fill-below: walk each sub-column along the line
        # and fill from the line's y down to the baseline. Done
        # before the line itself so the line draws on top.
        my $fill-color = self.theme.graph-fill.fg // $color;
        if $!fill-below {
            for ^(@points.elems - 1) -> $k {
                my ($x0, $y0) = @points[$k];
                my ($x1, $y1) = @points[$k + 1];
                my $dx = $x1 - $x0;
                my $start = min($x0, $x1);
                my $end   = max($x0, $x1);
                for $start .. $end -> $sx {
                    my $line-y = $dx == 0
                        ?? $y0
                        !! ($y0 * (1 - ($sx - $x0) / $dx)
                            + $y1 * (($sx - $x0) / $dx)).round.Int;
                    my $from = min($line-y, $baseline-sub-y);
                    my $to   = max($line-y, $baseline-sub-y);
                    for $from .. $to -> $fy {
                        self!set-subcell(%cells, $sx, $fy,
                                         $axis-cols, $fill-color);
                    }
                }
            }
        }

        # Lines between consecutive points.
        for ^(@points.elems - 1) -> $k {
            my ($x0, $y0) = @points[$k];
            my ($x1, $y1) = @points[$k + 1];
            self!draw-line(%cells, $x0, $y0, $x1, $y1, $axis-cols, $color);
        }
        # Single-point case: still place the dot.
        if @points.elems == 1 {
            my ($sx, $sy) = @points[0];
            self!set-subcell(%cells, $sx, $sy, $axis-cols, $color);
        }
    }

    # Composite cells.
    for %cells.kv -> $key, %v {
        my ($r, $c) = $key.split(',').map(*.Int);
        next if $r >= $body-rows || $c >= self.cols;
        my $glyph = chr(0x2800 + %v<bits>);
        my $style = Selkie::Style.new(fg => %v<color>);
        self.apply-style($style);
        ncplane_putstr_yx(self.plane, $r, $c, $glyph);
    }
}

# Set a single sub-cell by (sub-x, sub-y) in body-relative coordinates.
# %cells is keyed by (cell-row, cell-col) of the WIDGET plane (axis-cols
# already added).
method !set-subcell(%cells, Int $sx, Int $sy, UInt $axis-cols, UInt $color) {
    return if $sx < 0 || $sy < 0;
    my $cell-row = $sy div 4;
    my $cell-col = $axis-cols + ($sx div 2);
    my $sub-col  = $sx mod 2;
    my $sub-row  = $sy mod 4;
    my $bit      = @BIT-FOR[$sub-col][$sub-row];

    my $key = "$cell-row,$cell-col";
    unless %cells{$key}:exists {
        %cells{$key} = %( bits => 0, color => $color );
    }
    %cells{$key}<bits>  +|= 1 +< $bit;
    %cells{$key}<color>  = $color;     # z-order: last wins
}

# DDA-style line rasterisation between two sub-cell points. Plots
# one dot per sub-column traversed, computing y by linear interpolation.
method !draw-line(%cells, Int $x0, Int $y0, Int $x1, Int $y1,
                  UInt $axis-cols, UInt $color) {
    my $dx = $x1 - $x0;
    if $dx == 0 {
        # Vertical line — plot every sub-row
        my $from = min($y0, $y1);
        my $to   = max($y0, $y1);
        for $from .. $to -> $sy {
            self!set-subcell(%cells, $x0, $sy, $axis-cols, $color);
        }
        return;
    }
    # Otherwise step along x, interpolate y
    my $start = min($x0, $x1);
    my $end   = max($x0, $x1);
    for $start .. $end -> $sx {
        my $t = ($sx - $x0) / $dx;
        my $sy = ($y0 * (1 - $t) + $y1 * $t).round.Int;
        self!set-subcell(%cells, $sx, $sy, $axis-cols, $color);
    }
}

method !color-for(Int $i, %series --> UInt) {
    return %series<color> if %series<color>:exists;
    my @palette = Selkie::Plot::Palette.series($!palette);
    @palette[$i mod @palette.elems];
}

method !draw-legend(@series, UInt $row) {
    return if $row >= self.rows;
    my $col = 0;
    my $label-style = self.theme.text;

    for @series.kv -> $i, %s {
        last if $col >= self.cols;
        my $color = self!color-for($i, %s);

        # Swatch
        my $swatch-style = Selkie::Style.new(fg => $color);
        self.apply-style($swatch-style);
        ncplane_putstr_yx(self.plane, $row, $col, '■');
        $col += 2;
        last if $col >= self.cols;

        # Label
        self.apply-style($label-style);
        my $text = (%s<label> // '').Str;
        my $available = self.cols - $col;
        my $clipped = $text.substr(0, $available);
        ncplane_putstr_yx(self.plane, $row, $col, $clipped);
        $col += $clipped.chars + 2;
    }
}
