=begin pod

=head1 NAME

Selkie::Widget::Legend - Color-swatch + label rows for chart series

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Legend;
use Selkie::Sizing;

# A vertical legend with three series. Each row is "■ label".
my $legend = Selkie::Widget::Legend.new(
    series      => [
        { label => 'cpu',     color => 0xE69F00 },
        { label => 'memory',  color => 0x56B4E9 },
        { label => 'iowait',  color => 0x009E73 },
    ],
    orientation => 'vertical',
    sizing      => Sizing.fixed(3),
);

# A horizontal legend — series laid out across one row, separated by spaces.
my $h-legend = Selkie::Widget::Legend.new(
    series      => @series,
    orientation => 'horizontal',
    sizing      => Sizing.fixed(1),
);

=end code

=head1 DESCRIPTION

Renders a color-coded series legend for chart widgets. Each entry is
a coloured swatch glyph (C<■>) followed by the series label. Labels
that don't fit are truncated with an ellipsis.

The legend is theme-aware: the swatch colors come from each series'
C<color> entry; label text uses C<self.theme.text>; the optional
background derives from C<self.theme.graph-legend-bg>.

=head2 Orientations

=item B<vertical> (default) — one series per row. Used in dashboards where the legend lives in a sidebar or column.
=item B<horizontal> — series laid out left-to-right separated by single spaces. Best for legends below a chart.

=head2 Truncation

When a label doesn't fit (the swatch + label exceeds the available
cells in its row/column), the label is truncated and ellipsised
(C<…>). For horizontal layouts that means the rightmost series get
clipped first; for vertical, individual labels are clipped per row.

=head1 EXAMPLES

=head2 Inline with a LineChart

=begin code :lang<raku>

use Selkie::Widget::LineChart;
use Selkie::Widget::Legend;
use Selkie::Layout::HBox;
use Selkie::Sizing;

my @series = (
    { label => 'p50', values => @p50, color => 0x4477AA },
    { label => 'p99', values => @p99, color => 0xEE6677 },
);

my $chart = Selkie::Widget::LineChart.new(
    series       => @series,
    show-legend  => False,            # we'll draw our own
);

my $legend = Selkie::Widget::Legend.new(
    series       => @series,
    orientation  => 'vertical',
);

my $row = Selkie::Layout::HBox.new;
$row.add($chart,  sizing => Sizing.flex);
$row.add($legend, sizing => Sizing.fixed(12));

=end code

=head2 Below a chart, single-row horizontal

=begin code :lang<raku>

my $legend = Selkie::Widget::Legend.new(
    series      => @series,
    orientation => 'horizontal',
    sizing      => Sizing.fixed(1),
);

my $stack = Selkie::Layout::VBox.new;
$stack.add($chart,  sizing => Sizing.flex);
$stack.add($legend, sizing => Sizing.fixed(1));

=end code

=head1 SEE ALSO

=item L<Selkie::Plot::Palette> — colorblind-safe series palettes for the C<color> entries
=item L<Selkie::Widget::LineChart> — composes a Legend internally when C<show-legend> is True
=item L<Selkie::Widget::BarChart>

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

unit class Selkie::Widget::Legend does Selkie::Widget;

#| List of series entries. Each entry is a hash with C<label> (Str) and
#| C<color> (UInt RGB). Order is rendering order — first entry is at
#| top (vertical) or left (horizontal).
has @.series;

#| C<vertical> (one row per series) or C<horizontal> (single row,
#| series separated by single spaces).
has Str $.orientation = 'vertical';

#| Glyph used for the color swatch. Defaults to a full block
#| (C<■> — U+25A0). Some terminals render this slightly narrower
#| than ideal; C<●> (U+25CF) and C<█> (U+2588) are common alternates.
has Str $.swatch = '■';

submethod TWEAK {
    die "Selkie::Widget::Legend: orientation must be vertical|horizontal"
            ~ " (got '$!orientation')"
        unless $!orientation eq 'vertical'|'horizontal';

    # Raku flattens `[{ k => v }]` (single-element array of one hash)
    # into a list of pairs because the inner `{}` parses as a Block
    # rather than a Hash literal in that position. Detect the
    # "flattened single hash" case and rebuild it. Multi-element
    # `[{...}, {...}]` already parses correctly.
    if @!series.elems > 0 && @!series.all ~~ Pair {
        # %(...) builds a real Hash from flattened pairs; {...} parses
        # as a Block when its content isn't a literal Pair.
        @!series = (%( |@!series ),);
    }
}

#|( Replace the series list and request a re-render. )
method set-series(@new) {
    @!series = @new;
    self.mark-dirty;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    # Optional background fill from theme.graph-legend-bg. Apply early
    # so the swatch / label foregrounds composite over it.
    my $bg = self.theme.graph-legend-bg;
    if $bg.bg.defined {
        self.apply-style($bg);
        for ^self.rows -> $r {
            ncplane_putstr_yx(self.plane, $r, 0, ' ' x self.cols);
        }
    }

    given $!orientation {
        when 'vertical'   { self!render-vertical }
        when 'horizontal' { self!render-horizontal }
    }

    self.clear-dirty;
}

method !render-vertical() {
    my $label-style = self.theme.text;
    my $row = 0;
    for @!series -> %s {
        last if $row >= self.rows;
        next unless self.cols > 0;

        # Swatch in series color
        my $swatch-style = Selkie::Style.new(fg => %s<color>);
        self.apply-style($swatch-style);
        ncplane_putstr_yx(self.plane, $row, 0, $!swatch);

        # Label after swatch + space
        my $label-start = $!swatch.chars + 1;
        if $label-start < self.cols {
            self.apply-style($label-style);
            my $available = self.cols - $label-start;
            my $text = truncate(%s<label>.Str, $available);
            ncplane_putstr_yx(self.plane, $row, $label-start, $text);
        }

        $row++;
    }
}

method !render-horizontal() {
    return if self.rows == 0 || self.cols == 0;
    my $label-style = self.theme.text;
    my $col = 0;

    for @!series -> %s {
        last if $col >= self.cols;

        # Swatch
        my $swatch-style = Selkie::Style.new(fg => %s<color>);
        self.apply-style($swatch-style);
        ncplane_putstr_yx(self.plane, 0, $col, $!swatch);
        $col += $!swatch.chars;
        last if $col >= self.cols;

        # Single space gap
        $col++;
        last if $col >= self.cols;

        # Label
        self.apply-style($label-style);
        my $remaining = self.cols - $col;
        # Reserve at least 2 cells for swatch+space of any subsequent
        # series; rather than skipping a series mid-render, just truncate.
        my $text = truncate(%s<label>.Str, $remaining);
        ncplane_putstr_yx(self.plane, 0, $col, $text);
        $col += $text.chars;

        # Gap before the next series
        $col += 2;
    }
}

# Truncate a string to fit in $width cells. If the string is longer,
# replace the trailing characters with '…' (so the truncated result
# is still $width cells wide).
sub truncate(Str $s, UInt $width --> Str) {
    return $s if $s.chars <= $width;
    return '' if $width == 0;
    return '…' if $width == 1;
    $s.substr(0, $width - 1) ~ '…';
}
