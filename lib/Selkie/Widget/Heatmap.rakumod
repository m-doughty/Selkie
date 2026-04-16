=begin pod

=head1 NAME

Selkie::Widget::Heatmap - Coloured grid for 2D numeric data

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Heatmap;
use Selkie::Sizing;

# A 4×4 grid of arbitrary numeric values. Each cell renders as a
# coloured block; colour comes from the viridis ramp by default.
my $h = Selkie::Widget::Heatmap.new(
    data => [
        [ 0.1, 0.3, 0.5, 0.7 ],
        [ 0.2, 0.4, 0.6, 0.8 ],
        [ 0.3, 0.5, 0.7, 0.9 ],
        [ 0.4, 0.6, 0.8, 1.0 ],
    ],
    sizing => Sizing.fixed(4),
);

# Custom ramp + explicit range (useful for diverging data around 0)
my $diverging = Selkie::Widget::Heatmap.new(
    data   => @correlation-matrix,
    ramp   => 'coolwarm',
    min    => -1.0,
    max    =>  1.0,
    sizing => Sizing.flex,
);

# Reactive
my $live = Selkie::Widget::Heatmap.new(
    store-path => <metrics utilization-grid>,
    sizing     => Sizing.flex,
);

=end code

=head1 DESCRIPTION

A heatmap renders a 2D grid of numeric values as a grid of coloured
cells. Each cell is filled with C<█> (full block); the foreground
colour comes from a ramp lookup keyed by the cell's value normalised
to C<[0, 1]>.

=head2 Colour ramps

Default ramp is C<viridis> (perceptually uniform, colourblind-safe).
Other ramps from L<Selkie::Plot::Palette>:

=item C<viridis> — purple → blue → teal → green → yellow
=item C<magma> — black → purple → magenta → cream
=item C<plasma> — deep blue → magenta → orange
=item C<coolwarm> — diverging blue → white → red, useful for signed data centred on zero
=item C<grayscale> — five steps of grey, accessibility fallback

Override per-widget with C<:ramp<name>>.

=head2 Range

By default the range C<[min, max]> auto-derives from the data extent.
Pass explicit C<:min> / C<:max> to fix it (essential for the
diverging C<coolwarm> ramp, where C<0> needs to map to the white
midpoint regardless of data extent).

C<NaN> values render with the C<text-dim> theme slot so missing
data is visually distinct from in-range zero.

=head2 Cell aspect ratio

Terminal cells are taller than they are wide (~2:1). Heatmaps
B<don't compensate for this> — each data cell renders as one
terminal cell, so a 10×10 data grid looks tall and narrow on
screen. To get a near-square render, double the columns
(repeat each cell horizontally) by pre-processing the data.

=head1 EXAMPLES

=head2 A 2D function evaluation

=begin code :lang<raku>

my @grid = (^16).map: -> $r {
    (^16).map: -> $c {
        my $x = ($c - 8) / 8;
        my $y = ($r - 8) / 8;
        sin(sqrt($x*$x + $y*$y) * 5);
    }
};

my $heatmap = Selkie::Widget::Heatmap.new(
    data   => @grid,
    ramp   => 'viridis',
    sizing => Sizing.fixed(16),
);

=end code

=head2 A correlation matrix with a diverging ramp

Diverging ramps map C<0> to white in the middle. Pin the range to
keep the centre stable as data updates:

=begin code :lang<raku>

my $heatmap = Selkie::Widget::Heatmap.new(
    data   => @corr-matrix,         # values in [-1, 1]
    ramp   => 'coolwarm',
    min    => -1,
    max    =>  1,
    sizing => Sizing.fixed(@corr-matrix.elems),
);

=end code

=head2 Custom palette via theme override

The ramp comes from L<Selkie::Plot::Palette>. To use a colour ramp
not included in Palette, render a custom heatmap by subclassing this
widget — or open a feature request to add the ramp to Palette
upstream.

=head1 SEE ALSO

=item L<Selkie::Plot::Palette> — the colour ramp definitions
=item L<Selkie::Widget::ScatterPlot> — for sparse 2D point data
=item L<Selkie::Widget::BarChart> — for 1D categorical data

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Plot::Palette;

unit class Selkie::Widget::Heatmap does Selkie::Widget;

#| 2D array of numeric values. Each row is one row of cells.
has @.data;

#| Reactive store path. Mutually exclusive with C<data>.
has Str @.store-path;

#| Named colour ramp from L<Selkie::Plot::Palette>. Default: C<viridis>.
has Str $.ramp = 'viridis';

#| Optional explicit lower bound. Auto-derived from data when unset.
has Real $.min;

#| Optional explicit upper bound. Auto-derived from data when unset.
has Real $.max;

#| Message rendered when there is no data. This is the expected
#| startup state for monitoring dashboards. Set to the empty string
#| to suppress.
has Str $.empty-message = 'No data';

submethod TWEAK {
    die "Selkie::Widget::Heatmap: pass at most one of :data or :store-path"
        if @!data.elems > 0 && @!store-path.elems > 0;

    # Realise each row into an Array once at construction. Callers
    # commonly build the grid via nested `(^N).map: { ... }`, which
    # produces Seqs (one-shot iterators). A TUI app renders the same
    # widget every frame — after the first render consumed the Seqs,
    # every subsequent render would see empty rows.
    @!data = @!data.map({ .list.Array }) if @!data.elems > 0;
}

method set-data(@new) {
    die "Selkie::Widget::Heatmap.set-data: only valid in :data mode"
        if @!store-path.elems > 0;
    @!data = @new.map({ .list.Array });
    self.mark-dirty;
}

method on-store-attached($store) {
    return unless @!store-path.elems > 0;
    self.once-subscribe(
        'heatmap-' ~ self.widget-id,
        |@!store-path,
    );
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my @grid = self!current-grid;
    if @grid.elems == 0 {
        self!render-empty;
        return self.clear-dirty;
    }

    my ($lo, $hi) = self!effective-range(@grid);
    my $range = $hi - $lo;
    # Avoid divide-by-zero for degenerate (all-equal) data — every
    # cell maps to ramp midpoint.
    $range = 1 if $range == 0;

    my $nan-style = self.theme.text-dim;

    for ^min(@grid.elems, self.rows) -> $r {
        my @row = @grid[$r].list;
        for ^min(@row.elems, self.cols) -> $c {
            my $v = @row[$c];
            my $glyph = '█';
            if !$v.defined || $v === NaN {
                self.apply-style($nan-style);
                ncplane_putstr_yx(self.plane, $r, $c, $glyph);
            } else {
                my $t = ($v.Real - $lo) / $range;
                $t = 0 if $t < 0;
                $t = 1 if $t > 1;
                my $color = Selkie::Plot::Palette.sample($!ramp, $t);
                self.apply-style(Selkie::Style.new(fg => $color));
                ncplane_putstr_yx(self.plane, $r, $c, $glyph);
            }
        }
    }

    self.clear-dirty;
}

method !current-grid(--> List) {
    # Static data was realised in TWEAK; store data may still be
    # Seq-shaped so realise it on read.
    if @!store-path.elems > 0 && self.store {
        my $val = self.store.get-in(|@!store-path);
        return $val.defined ?? $val.map({ .list.Array }).list !! ();
    }
    @!data.list;
}

method !render-empty() {
    return if $!empty-message eq '' || self.rows == 0 || self.cols == 0;
    self.apply-style(self.theme.text-dim);
    my $msg = $!empty-message.substr(0, self.cols);
    my $row = self.rows div 2;
    my $col = max(0, (self.cols - $msg.chars) div 2);
    ncplane_putstr_yx(self.plane, $row, $col, $msg);
}

method !effective-range(@grid --> List) {
    return ($!min // 0, $!max // 1) if @grid.elems == 0;
    my @flat = @grid.map(*.list).flat
                    .grep({ .defined && $_ !=== NaN });
    return ($!min // 0, $!max // 1) if @flat.elems == 0;
    my $lo = $!min // @flat.min;
    my $hi = $!max // @flat.max;
    ($lo, $hi);
}
