=begin pod

=head1 NAME

Selkie::Widget::ScatterPlot - 2D point plot using braille sub-cell dots

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::ScatterPlot;
use Selkie::Sizing;

# Single-series scatter — auto-derives axis ranges from the data.
# Points are Pairs (x => y) so Raku doesn't flatten the list.
my @points = (1..50).map: { (rand * 100) => (rand * 100) };
my $sp = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'samples', points => @points },
    ],
    sizing => Sizing.flex,
);

# Multi-series with explicit colours
my $sp2 = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'group A', points => @group-a, color => 0xE69F00 },
        { label => 'group B', points => @group-b, color => 0x56B4E9 },
    ],
    sizing => Sizing.flex,
);

# Tip: use Pair (x => y), [x, y] arrays, or hash {x => , y => } per
# point. Don't use bare lists `(x, y)` — Raku flattens them in
# array context and your single-point scatter becomes two
# independent values.

# Reactive
my $live = Selkie::Widget::ScatterPlot.new(
    store-path => <viz scatter-data>,
    sizing     => Sizing.flex,
);

=end code

=head1 DESCRIPTION

A scatter plot of 2D points. Uses Unicode braille (U+2800-U+28FF)
for B<sub-cell> resolution: each terminal cell holds a 2×4 grid of
dot positions (8 dots per cell). A 50-cell-wide plot can resolve
100 distinct x-positions, and a 20-cell-tall plot can resolve 80
distinct y-positions.

=head2 The braille dot grid

Each braille codepoint encodes which of 8 sub-cell dots are filled:

  0 3
  1 4
  2 5
  6 7

The codepoint is C<U+2800 + bit-pattern>, where bit N controls dot N.
A cell with all 8 dots filled is C<⣿> (U+28FF). A cell with no dots
is C<⠀> (U+2800).

=head2 Multi-series colour collision

Each braille cell renders with a single foreground colour. When two
series have dots in the same 2×4 sub-cell window, the cell's colour
is determined by the C<:overlap> setting:

=item C<z-order> (default) — the last-drawn series wins the cell's colour. The earlier series' dots are still drawn but they take the later series' colour.

This is a documented limitation of single-foreground terminal
rendering. For non-overlapping multi-series, the colour assignment
is always correct. For overlapping data, prefer faceted layouts
(separate scatter plots per series) over single-plot overlay.

=head2 Range

Each axis range auto-derives from the data extent. Pass explicit
C<:x-min>, C<:x-max>, C<:y-min>, C<:y-max> to fix any of them. Useful
when streaming so the axes don't jitter as new points expand the
range.

=head1 EXAMPLES

=head2 Single cluster

=begin code :lang<raku>

my @cluster = (1..50).map: {
    (50 + rand * 20 - 10, 50 + rand * 20 - 10);
};
my $sp = Selkie::Widget::ScatterPlot.new(
    series => [{ label => 'cluster', points => @cluster }],
    x-min  => 0, x-max => 100,
    y-min  => 0, y-max => 100,
    sizing => Sizing.flex,
);

=end code

=head2 Two clusters with distinct colours

=begin code :lang<raku>

my $sp = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'cluster A', points => @a, color => 0xE69F00 },
        { label => 'cluster B', points => @b, color => 0x009E73 },
    ],
    sizing => Sizing.flex,
);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::LineChart> — connects points with lines (also braille)
=item L<Selkie::Widget::Heatmap> — for 2D data on a regular grid
=item L<Selkie::Plot::Palette> — colourblind-safe series palettes

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Plot::Scaler;
use Selkie::Plot::Palette;

unit class Selkie::Widget::ScatterPlot does Selkie::Widget;

# Bit positions for the 8 dots in a braille cell. Layout (column,row):
#   bit 0 = (0, 0)    bit 3 = (1, 0)
#   bit 1 = (0, 1)    bit 4 = (1, 1)
#   bit 2 = (0, 2)    bit 5 = (1, 2)
#   bit 6 = (0, 3)    bit 7 = (1, 3)
#
# Sub-cell coordinates within a 2×4 window. Used to pack a (sub-row,
# sub-col) location into the bit position.
my @BIT-FOR = (
    # [sub-col][sub-row] → bit
    [0, 1, 2, 6],   # sub-col 0
    [3, 4, 5, 7],   # sub-col 1
);

#| List of series. Each series is a hash with C<label> (Str),
#| C<points> (list of (x, y) pairs), and optional C<color> (UInt RGB).
has @.series;

#| Reactive store path. Mutually exclusive with C<series>.
has Str @.store-path;

#| Series-color palette. Used when individual series don't specify
#| C<color>.
has Str $.palette = 'okabe-ito';

#| Optional explicit X axis bounds. Auto-derived when unset.
has Real $.x-min;
has Real $.x-max;

#| Optional explicit Y axis bounds. Auto-derived when unset.
has Real $.y-min;
has Real $.y-max;

#| How to handle cells where multiple series have dots. Currently
#| only C<z-order> is supported (last-drawn wins the colour).
has Str $.overlap = 'z-order';

#| Message rendered when there are no points. The default is the
#| expected startup state for monitoring dashboards. Set to the
#| empty string to suppress.
has Str $.empty-message = 'No data';

submethod TWEAK {
    die "Selkie::Widget::ScatterPlot: pass at most one of :series or :store-path"
        if @!series.elems > 0 && @!store-path.elems > 0;
    die "Selkie::Widget::ScatterPlot: overlap must be 'z-order'"
        unless $!overlap eq 'z-order';

    if @!series.elems > 0 && @!series.all ~~ Pair {
        # %( |@!series ) is the right way to construct a Hash from a
        # flattened list of pairs; { |@!series } parses as a Block.
        @!series = (%( |@!series ),);
    }

    # Realise each series' points once at construction. Callers
    # commonly build points via `.map: { ... }`, which returns a
    # one-shot Seq. Long-lived TUI apps re-render every frame; after
    # the first render consumed the Seq, subsequent frames would see
    # an empty points list.
    @!series = @!series.map(-> %s {
        my %copy = %s;
        %copy<points> = (%s<points> // ()).list.Array if %s<points>:exists;
        %copy;
    });
}

method on-store-attached($store) {
    return unless @!store-path.elems > 0;
    self.once-subscribe(
        'scatter-' ~ self.widget-id,
        |@!store-path,
    );
}

method set-series(@new) {
    die "Selkie::Widget::ScatterPlot.set-series: only valid in :series mode"
        if @!store-path.elems > 0;
    @!series = @new.map(-> %s {
        my %copy = %s;
        %copy<points> = (%s<points> // ()).list.Array if %s<points>:exists;
        %copy;
    });
    self.mark-dirty;
}

#|( Compute the braille codepoint for a given bit pattern (0..255).
    Pure function, exhaustively unit-testable. )
method braille-glyph(UInt $bits where 0..255 --> Str) {
    chr(0x2800 + $bits);
}

#|( Compute the bit position within a braille cell for a sub-cell
    coordinate. C<$sub-col> is 0 or 1; C<$sub-row> is 0..3. Returns
    a bit index 0..7 suitable for use with C<braille-glyph>. )
method braille-bit(UInt $sub-col where 0..1, UInt $sub-row where 0..3 --> UInt) {
    @BIT-FOR[$sub-col][$sub-row];
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);
    return self.clear-dirty if self.rows == 0 || self.cols == 0;

    my @series = self!current-series;
    my $total-points = @series.map({ (.<points> // ()).elems }).sum;
    if @series.elems == 0 || $total-points == 0 {
        self!render-empty;
        return self.clear-dirty;
    }

    # Per-cell state: bit pattern + colour. We re-render each cell at
    # the end with z-order semantics for colour.
    my %cells;       # "$row,$col" => { bits => UInt, color => UInt }

    my ($x-lo, $x-hi, $y-lo, $y-hi) = self!effective-ranges(@series);
    my $x-scaler = Selkie::Plot::Scaler.linear(
        min => $x-lo, max => $x-hi, cells => self.cols * 2,
    );
    my $y-scaler = Selkie::Plot::Scaler.linear(
        min => $y-lo, max => $y-hi, cells => self.rows * 4, :invert,
    );

    for @series.kv -> $i, %s {
        my $color = self!color-for($i, %s);
        for (%s<points> // ()).list -> $point {
            my ($x, $y) = self!unpack-point($point);
            next unless $x.defined && $y.defined;
            next if $x === NaN || $y === NaN;
            my $sub-x = $x-scaler.value-to-cell($x.Real);
            my $sub-y = $y-scaler.value-to-cell($y.Real);
            next unless $sub-x.defined && $sub-y.defined;

            my $cell-row = $sub-y div 4;
            my $cell-col = $sub-x div 2;
            my $sub-row  = $sub-y mod 4;
            my $sub-col  = $sub-x mod 2;
            my $bit      = self.braille-bit($sub-col.UInt, $sub-row.UInt);

            my $key = "$cell-row,$cell-col";
            unless %cells{$key}:exists {
                %cells{$key} = { bits => 0, color => $color };
            }
            %cells{$key}<bits>  +|= 1 +< $bit;
            %cells{$key}<color>  = $color;       # z-order: last wins
        }
    }

    for %cells.kv -> $key, %v {
        my ($r, $c) = $key.split(',').map(*.Int);
        my $glyph = self.braille-glyph(%v<bits>);
        my $style = Selkie::Style.new(fg => %v<color>);
        self.apply-style($style);
        ncplane_putstr_yx(self.plane, $r, $c, $glyph);
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

method !current-series(--> List) {
    # Static series were realised in TWEAK; store data may still be
    # Seq-shaped so realise on read.
    sub realise(@list --> List) {
        @list.map(-> %s {
            my %copy = %s;
            %copy<points> = (%s<points> // ()).list.Array if %s<points>:exists;
            %copy;
        }).list;
    }
    if @!store-path.elems > 0 && self.store {
        my $val = self.store.get-in(|@!store-path);
        return $val.defined ?? realise($val.list) !! ();
    }
    @!series.list;
}

method !effective-ranges(@series --> List) {
    my @xs;
    my @ys;
    for @series -> %s {
        for (%s<points> // ()).list -> $point {
            my ($x, $y) = self!unpack-point($point);
            @xs.push($x) if $x.defined && $x !=== NaN;
            @ys.push($y) if $y.defined && $y !=== NaN;
        }
    }
    my $x-lo = $!x-min // (@xs.min // 0);
    my $x-hi = $!x-max // (@xs.max // 1);
    my $y-lo = $!y-min // (@ys.min // 0);
    my $y-hi = $!y-max // (@ys.max // 1);
    if $x-lo == $x-hi { $x-hi = $x-lo + 1 }
    if $y-lo == $y-hi { $y-hi = $y-lo + 1 }
    ($x-lo, $x-hi, $y-lo, $y-hi);
}

method !unpack-point($p --> List) {
    given $p {
        when Pair         { return $p.key, $p.value }
        when Positional   { return $p[0], $p[1] }
        when Associative  { return $p<x>, $p<y> }
        default           { return Real, Real }
    }
}

method !color-for(Int $i, %series --> UInt) {
    return %series<color> if %series<color>:exists;
    my @palette = Selkie::Plot::Palette.series($!palette);
    @palette[$i mod @palette.elems];
}
