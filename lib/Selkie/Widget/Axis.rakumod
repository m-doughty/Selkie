=begin pod

=head1 NAME

Selkie::Widget::Axis - Labelled tick axis for chart widgets

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Axis;
use Selkie::Sizing;

# A bottom axis covering [0, 100] with five ticks.
my $axis = Selkie::Widget::Axis.new(
    edge       => 'bottom',
    min        => 0,
    max        => 100,
    tick-count => 5,
    sizing     => Sizing.fixed(2),    # 1 row line + 1 row labels
);

# A left axis for a y-axis; reserves 5 columns by default for labels.
my $left = Selkie::Widget::Axis.new(
    edge       => 'left',
    min        => 0,
    max        => 1.0,
    tick-count => 6,
    sizing     => Sizing.fixed(6),
);

=end code

=head1 DESCRIPTION

Renders a labelled axis along one of the four edges of its plane:
C<top>, C<bottom>, C<left>, or C<right>. The axis is the visual
companion to chart widgets — a horizontal axis sits below a chart
body, a vertical axis sits to its left or right.

Internally the axis builds its own L<Selkie::Plot::Scaler> and
L<Selkie::Plot::Ticks> matched to its current plane dimensions. So
when a chart widget composes an Axis, it just passes the axis's
data range (min, max) and tick count — the axis figures out its own
cell mapping.

Y-axes (C<left>, C<right>) automatically use C<:invert> so the
maximum value sits at the top of the plane (terminal row 0 is the
I<top> of the screen, which by chart convention should hold the
largest value).

=head2 Glyphs

The four edges use these box-drawing glyphs:

=table
  Edge     | Line  | Tick  | Label position
  bottom   | ─     | ┬     | row below the line, centred on the tick column
  top      | ─     | ┴     | row above the line, centred on the tick column
  left     | │     | ┤     | columns to the left of the line, right-aligned to the tick row
  right    | │     | ├     | columns to the right of the line, left-aligned to the tick row

All glyphs render in the C<graph-axis> theme slot; labels render in
C<graph-axis-label>. Override either per-theme or via custom slots
to restyle.

=head2 Sizing

=item B<Top / bottom> axes need 2 rows: one for the line and one for labels. C<reserved-rows> returns 2.
=item B<Left / right> axes need C<widest-label + 1> columns: the labels plus the line. Width depends on the data range — call C<reserved-cols> to get the actual budget.

Use these helpers when sizing parent containers so the axis gets
exactly the rows / columns it needs:

=begin code :lang<raku>

my $axis = Selkie::Widget::Axis.new(edge => 'left', min => 0, max => 1000);
$container.add: $axis, sizing => Sizing.fixed($axis.reserved-cols);

=end code

=head1 EXAMPLES

=head2 A standalone bottom axis

=begin code :lang<raku>

use Selkie::Widget::Axis;
use Selkie::Sizing;

my $axis = Selkie::Widget::Axis.new(
    edge       => 'bottom',
    min        => 0,
    max        => 1000,
    tick-count => 5,
    sizing     => Sizing.fixed(2),
);

# Drop into a VBox above other content, or into a chart widget that
# delegates the bottom strip to it.

=end code

=head2 Composed inside a chart layout

A chart usually composes a bottom axis below the body and a left axis
to its left:

=begin code :lang<raku>

use Selkie::Widget::Axis;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;

my $left   = Selkie::Widget::Axis.new(edge => 'left',   min => 0, max => 100);
my $bottom = Selkie::Widget::Axis.new(edge => 'bottom', min => 0, max => 60);

my $body = my-chart-body();   # a LineChart, BarChart, etc.

my $row    = Selkie::Layout::HBox.new;
$row.add: $left, sizing => Sizing.fixed($left.reserved-cols);
$row.add: $body, sizing => Sizing.flex;

my $stack  = Selkie::Layout::VBox.new;
$stack.add: $row,    sizing => Sizing.flex;
$stack.add: $bottom, sizing => Sizing.fixed($bottom.reserved-rows);

=end code

=head1 SEE ALSO

=item L<Selkie::Plot::Scaler> — the value→cell mapping the axis uses
=item L<Selkie::Plot::Ticks> — the nice-number tick generation
=item L<Selkie::Charts> — overview of the chart family

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Plot::Scaler;
use Selkie::Plot::Ticks;

unit class Selkie::Widget::Axis does Selkie::Widget;

#| Which edge to render on: C<top>, C<bottom>, C<left>, or C<right>.
has Str  $.edge       = 'bottom';

#| Lower bound of the axis range.
has Real $.min        is required;

#| Upper bound of the axis range.
has Real $.max        is required;

#| Approximate tick count; the actual count depends on Heckbert's
#| nice-number choice (see L<Selkie::Plot::Ticks>).
has UInt $.tick-count = 5;

#| Whether to draw the connecting axis line. Disable when stacking
#| multiple axes on the same edge or when the chart body provides its
#| own border.
has Bool $.show-line  = True;

submethod TWEAK {
    die "Selkie::Widget::Axis: edge must be one of top|bottom|left|right (got '$!edge')"
        unless $!edge eq 'top'|'bottom'|'left'|'right';
    die "Selkie::Widget::Axis: min ($!min) must be <= max ($!max)"
        if $!min > $!max;
}

#|( Number of rows this axis needs to render properly. Returns 2 for
    horizontal axes (line + labels), 0 for vertical (caller decides
    height). Use to size the axis's container correctly. )
method reserved-rows(--> UInt) {
    $!edge eq 'top'|'bottom' ?? 2 !! 0;
}

#|( Number of columns this axis needs to render properly. For vertical
    axes, returns the widest tick label's width plus one (for the
    axis line). For horizontal axes, returns 0 (caller decides width). )
method reserved-cols(--> UInt) {
    return 0 unless $!edge eq 'left'|'right';
    my $ticks = self!build-ticks;
    my $widest = $ticks.labels.map(*.chars).max // 0;
    $widest + 1;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my $axis-style  = self.theme.graph-axis;
    my $label-style = self.theme.graph-axis-label;

    given $!edge {
        when 'bottom' { self!render-bottom($axis-style, $label-style) }
        when 'top'    { self!render-top($axis-style, $label-style) }
        when 'left'   { self!render-left($axis-style, $label-style) }
        when 'right'  { self!render-right($axis-style, $label-style) }
    }

    self.clear-dirty;
}

method !build-ticks(--> Selkie::Plot::Ticks) {
    Selkie::Plot::Ticks.nice(
        min => $!min, max => $!max, count => $!tick-count,
    );
}

method !build-scaler(UInt $cells, Bool :$invert = False --> Selkie::Plot::Scaler) {
    # Degenerate case — caller's responsibility to avoid 0-cell planes,
    # but we don't crash if it happens. Return an arbitrary 1-cell
    # scaler since nothing will render anyway.
    my $safe-cells = max($cells, 1);
    Selkie::Plot::Scaler.linear(
        min => $!min, max => $!max, cells => $safe-cells, :$invert,
    );
}

method !render-bottom($axis-style, $label-style) {
    return if self.cols == 0 || self.rows == 0;
    my $scaler = self!build-scaler(self.cols);
    my $ticks  = self!build-ticks;

    self.apply-style($axis-style);
    if $!show-line {
        ncplane_putstr_yx(self.plane, 0, 0, '─' x self.cols);
    }
    for $ticks.values -> $v {
        my $col = $scaler.value-to-cell($v);
        next without $col.defined;
        ncplane_putstr_yx(self.plane, 0, $col, '┬') if $!show-line;
    }

    return if self.rows < 2;
    self.apply-style($label-style);
    for $ticks.values.kv -> $i, $v {
        my $col = $scaler.value-to-cell($v);
        next without $col.defined;
        self!draw-horizontal-label(1, $col, $ticks.labels[$i]);
    }
}

method !render-top($axis-style, $label-style) {
    return if self.cols == 0 || self.rows == 0;
    my $scaler = self!build-scaler(self.cols);
    my $ticks  = self!build-ticks;

    # Line is on the LAST row; labels are above (row 0 ... row last-1).
    my $line-row = self.rows - 1;

    self.apply-style($axis-style);
    if $!show-line {
        ncplane_putstr_yx(self.plane, $line-row, 0, '─' x self.cols);
    }
    for $ticks.values -> $v {
        my $col = $scaler.value-to-cell($v);
        next without $col.defined;
        ncplane_putstr_yx(self.plane, $line-row, $col, '┴') if $!show-line;
    }

    return if self.rows < 2;
    self.apply-style($label-style);
    for $ticks.values.kv -> $i, $v {
        my $col = $scaler.value-to-cell($v);
        next without $col.defined;
        self!draw-horizontal-label($line-row - 1, $col, $ticks.labels[$i]);
    }
}

method !render-left($axis-style, $label-style) {
    return if self.cols == 0 || self.rows == 0;
    # Y-axes invert: the maximum value sits at row 0 (top of screen).
    my $scaler = self!build-scaler(self.rows, :invert);
    my $ticks  = self!build-ticks;
    my $line-col = self.cols - 1;

    self.apply-style($axis-style);
    if $!show-line {
        for ^self.rows -> $r {
            ncplane_putstr_yx(self.plane, $r, $line-col, '│');
        }
    }
    for $ticks.values -> $v {
        my $row = $scaler.value-to-cell($v);
        next without $row.defined;
        ncplane_putstr_yx(self.plane, $row, $line-col, '┤') if $!show-line;
    }

    # Labels right-aligned in the columns to the left of the line.
    return if $line-col == 0;
    self.apply-style($label-style);
    for $ticks.values.kv -> $i, $v {
        my $row = $scaler.value-to-cell($v);
        next without $row.defined;
        my $text = $ticks.labels[$i];
        my $start = $line-col - $text.chars;
        $start = 0 if $start < 0;
        ncplane_putstr_yx(self.plane, $row, $start, $text.substr(0, $line-col));
    }
}

method !render-right($axis-style, $label-style) {
    return if self.cols == 0 || self.rows == 0;
    my $scaler = self!build-scaler(self.rows, :invert);
    my $ticks  = self!build-ticks;
    my $line-col = 0;

    self.apply-style($axis-style);
    if $!show-line {
        for ^self.rows -> $r {
            ncplane_putstr_yx(self.plane, $r, $line-col, '│');
        }
    }
    for $ticks.values -> $v {
        my $row = $scaler.value-to-cell($v);
        next without $row.defined;
        ncplane_putstr_yx(self.plane, $row, $line-col, '├') if $!show-line;
    }

    # Labels left-aligned in the columns to the right of the line.
    return if self.cols < 2;
    self.apply-style($label-style);
    for $ticks.values.kv -> $i, $v {
        my $row = $scaler.value-to-cell($v);
        next without $row.defined;
        my $text = $ticks.labels[$i];
        my $available = self.cols - 1;
        ncplane_putstr_yx(self.plane, $row, 1, $text.substr(0, $available));
    }
}

# Center a label under/over a tick column, clamping to the plane width
# and avoiding negative starts when the label is wider than the
# remaining cells.
method !draw-horizontal-label(UInt $row, UInt $tick-col, Str $text) {
    my $half = $text.chars div 2;
    my Int $start = $tick-col.Int - $half;
    $start = 0 if $start < 0;
    my $max-start = self.cols.Int - $text.chars.Int;
    $start = $max-start if $start > $max-start;
    $start = 0 if $start < 0;
    my $clipped = $text.substr(0, self.cols - $start);
    ncplane_putstr_yx(self.plane, $row, $start, $clipped);
}
