=begin pod

=head1 NAME

Selkie::Widget::BarChart - Categorical bar chart, vertical or horizontal

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::BarChart;
use Selkie::Sizing;

# Vertical bars (default)
my $bars = Selkie::Widget::BarChart.new(
    data => [
        { label => 'apples',  value => 12 },
        { label => 'pears',   value =>  7 },
        { label => 'cherries',value => 15 },
        { label => 'plums',   value =>  4 },
    ],
    sizing => Sizing.flex,
);

# Horizontal bars
my $hbars = Selkie::Widget::BarChart.new(
    data        => @data,
    orientation => 'horizontal',
    sizing      => Sizing.flex,
);

# Reactive — read from a store path
my $live = Selkie::Widget::BarChart.new(
    store-path => <stats counts>,
    sizing     => Sizing.flex,
);

=end code

=head1 DESCRIPTION

A categorical bar chart. Each entry is a labelled value; entries are
laid out across the chart body with one bar per entry. The
B<orientation> determines the bar direction:

=item B<vertical> (default) — bars rise from the bottom; labels along the bottom edge; values along the left edge.
=item B<horizontal> — bars extend rightward from the left; labels along the left edge; values along the top edge.

Bar heights / widths use 1/8-cell precision via the Unicode block
glyphs (C<▁▂▃▄▅▆▇█> vertically, C<▏▎▍▌▋▊▉█> horizontally) so a bar
can be C<3.625> cells tall, not just integer cells.

=head2 Construction modes

Same as L<Selkie::Widget::Sparkline>:

=item B<Static> — pass C<:data([...])> with one hash per bar (C<label>, C<value>, optional C<color>).
=item B<Reactive> — pass C<:store-path<a b c>> to read the data array from a store path; the widget re-renders when the value changes.

The two modes are mutually exclusive.

=head2 Coloring

Each bar's color comes from one of three sources, in priority order:

=item Per-bar override: C<{ label => 'foo', value => 12, color => 0xFF0000 }>
=item The named palette specified by C<:palette> (default C<okabe-ito>) — colors cycle if there are more bars than palette entries
=item C<self.theme.graph-line> as a fallback for any bar without a color and no palette match

See L<Selkie::Plot::Palette> for the available palettes.

=head2 Range

Y-range (vertical) / X-range (horizontal) auto-derives from the data:
the lower bound is C<0> (or the data minimum if negative), the upper
bound is the data maximum padded outward by Heckbert's nice-number
choice (so the top tick lands on a round number).

Pass C<:min> and C<:max> to fix the range.

=head1 EXAMPLES

=head2 Simple categorical comparison

=begin code :lang<raku>

my $chart = Selkie::Widget::BarChart.new(
    data => [
        { label => 'Q1', value => 1230 },
        { label => 'Q2', value => 1875 },
        { label => 'Q3', value => 2042 },
        { label => 'Q4', value => 1611 },
    ],
    sizing => Sizing.flex,
);

=end code

=head2 Multi-color with a palette override

=begin code :lang<raku>

my $chart = Selkie::Widget::BarChart.new(
    data    => @data,
    palette => 'tol-bright',
    sizing  => Sizing.flex,
);

=end code

=head2 Per-bar color (status indicator)

=begin code :lang<raku>

my @data = $tasks.map: -> $t {
    {
        label => $t.name,
        value => $t.duration-ms,
        color => $t.status eq 'failed' ?? 0xCC4444 !! 0x44AA44,
    }
};
my $chart = Selkie::Widget::BarChart.new(:@data, sizing => Sizing.flex);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Histogram> — bins a numeric series and feeds it into BarChart
=item L<Selkie::Widget::Sparkline> — for a single inline trend bar
=item L<Selkie::Plot::Palette> — series colors

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Plot::Scaler;
use Selkie::Plot::Ticks;
use Selkie::Plot::Palette;

unit class Selkie::Widget::BarChart does Selkie::Widget;

# Vertical 1/8-cell glyphs, lowest to highest (index 0 = empty, 8 = full)
constant @V-LEVELS = ' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█';

# Horizontal 1/8-cell glyphs, narrowest to widest
constant @H-LEVELS = ' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█';

#| List of bar entries. Each entry is a hash with C<label> (Str),
#| C<value> (Real), and optional C<color> (UInt RGB).
has @.data;

#| Reactive store path. Mutually exclusive with C<data>.
has Str @.store-path;

#| C<vertical> (bars rise from the bottom) or C<horizontal> (bars
#| extend right from the left).
has Str $.orientation = 'vertical';

#| Named series palette for bar colors. See L<Selkie::Plot::Palette>.
has Str $.palette = 'okabe-ito';

#| Whether to draw the value axis (left for vertical, top for
#| horizontal). Disable when the chart is composed in a layout that
#| supplies its own axis.
has Bool $.show-axis = True;

#| Whether to draw category labels (bottom for vertical, left for
#| horizontal).
has Bool $.show-labels = True;

#| Optional explicit lower bound. When unset, derived from the data
#| (C<min(0, min-data)>).
has Real $.min;

#| Optional explicit upper bound. When unset, derived from the data
#| (C<max-data>, padded by Heckbert).
has Real $.max;

#| Approximate tick count for the value axis.
has UInt $.tick-count = 5;

#| Message rendered when there are no bars. The default is the
#| expected startup state for monitoring dashboards. Set to the
#| empty string to suppress.
has Str $.empty-message = 'No data';

submethod TWEAK {
    die "Selkie::Widget::BarChart: pass at most one of :data or :store-path"
        if @!data.elems > 0 && @!store-path.elems > 0;
    die "Selkie::Widget::BarChart: orientation must be vertical|horizontal"
        unless $!orientation eq 'vertical'|'horizontal';

    # %(...) constructs a Hash from a flat pair list; {...} would parse
    # as a Block in this position. Same Raku gotcha Legend handles.
    if @!data.elems > 0 && @!data.all ~~ Pair {
        @!data = (%( |@!data ),);
    }
}

method on-store-attached($store) {
    return unless @!store-path.elems > 0;
    self.once-subscribe(
        'barchart-' ~ self.widget-id,
        |@!store-path,
    );
}

method set-data(@new) {
    die "Selkie::Widget::BarChart.set-data: only valid in :data mode"
        if @!store-path.elems > 0;
    @!data = @new;
    self.mark-dirty;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);
    return self.clear-dirty if self.rows == 0 || self.cols == 0;

    my @entries = self!current-data;
    if @entries.elems == 0 {
        self!render-empty;
        return self.clear-dirty;
    }

    given $!orientation {
        when 'vertical'   { self!render-vertical(@entries) }
        when 'horizontal' { self!render-horizontal(@entries) }
    }

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

method !current-data(--> List) {
    if @!store-path.elems > 0 && self.store {
        my $val = self.store.get-in(|@!store-path);
        return ($val.defined ?? $val.list !! ()).list;
    }
    @!data.list;
}

method !effective-range(@entries --> List) {
    my @vals = @entries.map(*.<value>).grep(*.defined);
    my $data-min = @vals.min // 0;
    my $data-max = @vals.max // 1;
    my $lo = $!min // min(0, $data-min);
    my $hi = $!max // $data-max;
    if $lo == $hi {
        $hi = $lo + 1;
    }
    ($lo, $hi);
}

method !color-for(Int $i, %entry --> UInt) {
    return %entry<color> if %entry<color>:exists;
    my @palette = Selkie::Plot::Palette.series($!palette);
    return @palette[$i mod @palette.elems];
}

method !render-vertical(@entries) {
    my ($lo, $hi) = self!effective-range(@entries);

    # Reserve rows for labels (bottom) and cols for axis (left)
    my $label-rows = $!show-labels ?? 1 !! 0;
    my $axis-cols  = $!show-axis ?? self!axis-width($lo, $hi) !! 0;

    my $body-rows = self.rows - $label-rows;
    my $body-cols = self.cols - $axis-cols;
    return if $body-rows <= 0 || $body-cols <= 0;

    # Draw value axis on the left
    if $!show-axis {
        self!draw-vertical-axis($lo, $hi, $body-rows, $axis-cols);
    }

    # Allocate bar columns
    my $n = @entries.elems;
    my $bar-width = max($body-cols div ($n * 2), 1);
    my $total-bar-cols = $bar-width * $n;
    my $gap = $n > 1
        ?? ($body-cols - $total-bar-cols) div ($n + 1)
        !! ($body-cols - $bar-width) div 2;
    $gap = max($gap, 0);

    # Draw bars
    for @entries.kv -> $i, %e {
        my $color = self!color-for($i, %e);
        my $val   = (%e<value> // 0).Real;

        my $start-col = $axis-cols + $gap + $i * ($bar-width + $gap);
        next if $start-col >= self.cols;
        my $width = min($bar-width, self.cols - $start-col);

        # Fractional height in 1/8-cells
        my $eighths = (($val - $lo) / ($hi - $lo) * $body-rows * 8).round.Int;
        $eighths = 0           if $eighths < 0;
        $eighths = $body-rows * 8 if $eighths > $body-rows * 8;
        my $full-cells = $eighths div 8;
        my $remainder  = $eighths mod 8;

        my $style = Selkie::Style.new(fg => $color);
        self.apply-style($style);

        # Bottom-up: full cells from row (body_rows-1) up to (body_rows - full_cells)
        for ^$full-cells -> $r {
            my $row = $body-rows - 1 - $r;
            for ^$width -> $w {
                ncplane_putstr_yx(self.plane, $row, $start-col + $w, '█');
            }
        }
        if $remainder > 0 {
            my $row = $body-rows - 1 - $full-cells;
            if $row >= 0 {
                my $glyph = @V-LEVELS[$remainder];
                for ^$width -> $w {
                    ncplane_putstr_yx(self.plane, $row, $start-col + $w, $glyph);
                }
            }
        }
    }

    # Draw labels in the bottom row
    if $!show-labels && $label-rows > 0 {
        my $label-style = self.theme.graph-axis-label;
        self.apply-style($label-style);
        for @entries.kv -> $i, %e {
            my $start-col = $axis-cols + $gap + $i * ($bar-width + $gap);
            next if $start-col >= self.cols;
            my $text = (%e<label> // '').Str;
            my $available = min($bar-width, self.cols - $start-col);
            my $clipped = $text.substr(0, $available);
            ncplane_putstr_yx(self.plane, self.rows - 1, $start-col, $clipped);
        }
    }
}

method !render-horizontal(@entries) {
    my ($lo, $hi) = self!effective-range(@entries);

    # Reserve cols for labels (left) and rows for axis (top)
    my $label-cols = $!show-labels ?? self!horizontal-label-width(@entries) !! 0;
    my $axis-rows  = $!show-axis ?? 1 !! 0;

    my $body-rows = self.rows - $axis-rows;
    my $body-cols = self.cols - $label-cols;
    return if $body-rows <= 0 || $body-cols <= 0;

    # Draw value axis on the top
    if $!show-axis {
        self!draw-horizontal-axis($lo, $hi, $body-cols, $label-cols);
    }

    # Allocate bar rows
    my $n = @entries.elems;
    my $bar-height = max($body-rows div ($n * 2), 1);
    my $total-bar-rows = $bar-height * $n;
    my $gap = $n > 1
        ?? ($body-rows - $total-bar-rows) div ($n + 1)
        !! ($body-rows - $bar-height) div 2;
    $gap = max($gap, 0);

    # Draw bars
    for @entries.kv -> $i, %e {
        my $color = self!color-for($i, %e);
        my $val   = (%e<value> // 0).Real;

        my $start-row = $axis-rows + $gap + $i * ($bar-height + $gap);
        next if $start-row >= self.rows;
        my $height = min($bar-height, self.rows - $start-row);

        my $eighths = (($val - $lo) / ($hi - $lo) * $body-cols * 8).round.Int;
        $eighths = 0              if $eighths < 0;
        $eighths = $body-cols * 8 if $eighths > $body-cols * 8;
        my $full-cells = $eighths div 8;
        my $remainder  = $eighths mod 8;

        my $style = Selkie::Style.new(fg => $color);
        self.apply-style($style);

        for ^$height -> $h {
            my $row = $start-row + $h;
            for ^$full-cells -> $c {
                ncplane_putstr_yx(self.plane, $row, $label-cols + $c, '█');
            }
            if $remainder > 0 && ($label-cols + $full-cells) < self.cols {
                ncplane_putstr_yx(self.plane, $row, $label-cols + $full-cells,
                                  @H-LEVELS[$remainder]);
            }
        }
    }

    # Draw labels on the left
    if $!show-labels && $label-cols > 0 {
        my $label-style = self.theme.graph-axis-label;
        self.apply-style($label-style);
        for @entries.kv -> $i, %e {
            my $start-row = $axis-rows + $gap + $i * ($bar-height + $gap);
            next if $start-row >= self.rows;
            my $text = (%e<label> // '').Str;
            my $clipped = $text.substr(0, $label-cols);
            # Center vertically across bar-height
            my $row = $start-row + $bar-height div 2;
            $row = min($row, self.rows - 1);
            ncplane_putstr_yx(self.plane, $row, 0, $clipped);
        }
    }
}

method !axis-width(Real $lo, Real $hi --> UInt) {
    my $ticks = Selkie::Plot::Ticks.nice(min => $lo, max => $hi, count => $!tick-count);
    (($ticks.labels.map(*.chars).max // 0) + 1).UInt;
}

method !horizontal-label-width(@entries --> UInt) {
    my $widest = @entries.map({ (.<label> // '').chars }).max // 0;
    min($widest, max(self.cols div 4, 6));
}

method !draw-vertical-axis(Real $lo, Real $hi, UInt $rows, UInt $axis-cols) {
    my $axis-style = self.theme.graph-axis;
    my $label-style = self.theme.graph-axis-label;

    my $line-col = $axis-cols - 1;
    my $scaler = Selkie::Plot::Scaler.linear(
        min => $lo, max => $hi, cells => $rows, :invert,
    );
    my $ticks = Selkie::Plot::Ticks.nice(min => $lo, max => $hi, count => $!tick-count);

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

method !draw-horizontal-axis(Real $lo, Real $hi, UInt $cols, UInt $label-cols) {
    my $axis-style = self.theme.graph-axis;
    my $label-style = self.theme.graph-axis-label;

    # Top-edge line at row 0; we'd render labels below the line if
    # there's room, but reserved 1 row only — so no labels in v1
    # for the horizontal axis. Just the line + tick marks.
    self.apply-style($axis-style);
    ncplane_putstr_yx(self.plane, 0, $label-cols, '─' x $cols);

    my $scaler = Selkie::Plot::Scaler.linear(
        min => $lo, max => $hi, cells => $cols,
    );
    my $ticks = Selkie::Plot::Ticks.nice(min => $lo, max => $hi, count => $!tick-count);

    for $ticks.values -> $v {
        my $col = $scaler.value-to-cell($v);
        next without $col.defined;
        next if $col >= $cols;
        ncplane_putstr_yx(self.plane, 0, $label-cols + $col, '┬');
    }
}
