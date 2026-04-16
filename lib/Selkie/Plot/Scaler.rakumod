=begin pod

=head1 NAME

Selkie::Plot::Scaler - Map a numeric domain onto a discrete cell range

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Plot::Scaler;

# A linear scaler that maps the domain [0, 100] onto a 20-cell axis.
my $s = Selkie::Plot::Scaler.linear(min => 0, max => 100, cells => 20);

$s.value-to-cell(0);     # → 0
$s.value-to-cell(50);    # → 10
$s.value-to-cell(100);   # → 19
$s.value-to-cell(150);   # → 19  (clamped)
$s.value-to-cell(-10);   # → 0   (clamped)
$s.cell-to-value(10);    # → 52.6315... (midpoint of cell 10)

# Inverted axis — cell 0 holds the maximum value, useful for y-axes
# where the top of the screen is row 0 but the largest value should
# render highest on the chart.
my $y = Selkie::Plot::Scaler.linear(
    min => 0, max => 100, cells => 20, :invert,
);
$y.value-to-cell(100);   # → 0    (top row)
$y.value-to-cell(0);     # → 19   (bottom row)

=end code

=head1 DESCRIPTION

A C<Selkie::Plot::Scaler> maps a numeric value in the domain
C<[min, max]> to an integer cell index in C<[0, cells-1]>. It's the
shared coordinate-mapping primitive used by every chart widget —
C<Sparkline>, C<BarChart>, C<LineChart>, C<ScatterPlot>, C<Heatmap>,
and the axes that label them.

The scaler is pure data: no notcurses, no widget, no I/O. It's
deterministic and exhaustively unit-testable, which matters because a
miscomputed mapping silently corrupts every chart that uses it.

=head2 The linear formula

For C<cells E<gt> 1>:

  cell = round( (value - min) / (max - min) * (cells - 1) )

then clamped to C<[0, cells-1]>. With C<:invert> the result is
flipped: C<cell = (cells - 1) - cell>.

The inverse C<cell-to-value> returns the value at the midpoint of the
target cell:

  value = (cell / (cells - 1)) * (max - min) + min

A round-trip C<cell-to-value(value-to-cell(v))> recovers C<v> within
C<± (max - min) / (2 * (cells - 1))> — the half-cell precision floor
imposed by the integer cell grid.

=head2 Edge cases

=item B<C<cells> must be E<gt> 0> — zero-cell scalers are nonsensical and throw.
=item B<C<min == max> degenerate range> — every value maps to the middle cell. C<cell-to-value> returns C<min> (which equals C<max>).
=item B<C<min E<gt> max>> — throws. Inverted I<axes> are expressed via C<:invert>, not via reversed bounds.
=item B<C<NaN> input> — C<value-to-cell> returns C<UInt> (the typed undef). NaN is propagated, not clamped, so callers can detect missing samples.
=item B<C<+Inf> / C<-Inf> input> — clamped to the corresponding edge cell (C<cells - 1> for C<+Inf>, C<0> for C<-Inf>; flipped under C<:invert>).
=item B<Out-of-domain value> — clamped to the nearest edge cell. No exception.

=head1 EXAMPLES

=head2 Composing scalers for a 2D plot

A scatter plot needs two scalers — one per axis. The y-scaler is
typically inverted because terminal row 0 is the I<top> of the screen
but charts conventionally place the maximum value I<at the top>.

=begin code :lang<raku>

my $x-scaler = Selkie::Plot::Scaler.linear(
    min => 0, max => $duration, cells => $width,
);
my $y-scaler = Selkie::Plot::Scaler.linear(
    min => $min-y, max => $max-y, cells => $height, :invert,
);

for @samples -> %point {
    my $col = $x-scaler.value-to-cell(%point<t>);
    my $row = $y-scaler.value-to-cell(%point<v>);
    plot-dot($row, $col);
}

=end code

=head2 Recovering tick values for axis labels

When generating axis tick labels (see L<Selkie::Plot::Ticks>) you want
the value at a given cell. C<cell-to-value> gives the cell midpoint:

=begin code :lang<raku>

my $axis-scaler = Selkie::Plot::Scaler.linear(
    min => 0, max => 1000, cells => 80,
);
say $axis-scaler.cell-to-value(0);    # → 0
say $axis-scaler.cell-to-value(40);   # → 506.32...
say $axis-scaler.cell-to-value(79);   # → 1000

=end code

=head1 SEE ALSO

=item L<Selkie::Plot::Ticks> — generates "nice" tick values for a domain
=item L<Selkie::Plot::Palette> — colorblind-safe series colors and ramps
=item L<Selkie::Widget::Axis> — renders ticks + labels along a chart edge

=end pod

unit class Selkie::Plot::Scaler;

#| Domain lower bound (inclusive).
has Real $.min;

#| Domain upper bound (inclusive).
has Real $.max;

#| Number of discrete cells in the target range. Must be > 0.
has UInt $.cells;

#| Whether to flip the mapping (cell 0 holds the maximum value).
has Bool $.invert = False;

#|( Linear scaler constructor.

    Throws if C<cells> is 0 or if C<min E<gt> max>. C<min == max> is
    permitted (degenerate range — every value maps to the middle cell).

    Use C<:invert> for axes where cell 0 should hold the maximum value
    (typically y-axes — terminal row 0 is the top of the screen, and
    charts conventionally render the largest value highest). )
method linear(::?CLASS:U:
              Real :$min!,
              Real :$max!,
              UInt :$cells!,
              Bool :$invert = False,
              --> ::?CLASS) {
    die "Selkie::Plot::Scaler.linear: cells must be > 0 (got 0)"
        if $cells == 0;
    die "Selkie::Plot::Scaler.linear: min ($min) must be <= max ($max);"
        ~ " use :invert to flip the cell direction"
        if $min > $max;
    self.bless(:$min, :$max, :$cells, :$invert);
}

#|( Map a value in the domain to a cell index in C<[0, cells-1]>.
    Out-of-domain values are clamped to the nearest edge. C<NaN>
    propagates as C<UInt> (the typed undef). C<±Inf> clamps to the
    corresponding edge. )
method value-to-cell(Real $value --> UInt) {
    return UInt if $value === NaN;

    # ±Inf clamps to the appropriate edge before the divide-by-range
    # computation can produce its own NaN/Inf.
    if $value == Inf {
        return $!invert ?? 0 !! ($!cells - 1);
    }
    if $value == -Inf {
        return $!invert ?? ($!cells - 1) !! 0;
    }

    # Single-cell axis: every value maps to cell 0.
    return 0 if $!cells == 1;

    # Degenerate domain (min == max): every value maps to the middle
    # cell. Pick floor((cells-1) / 2) for symmetry.
    if $!min == $!max {
        return ($!cells - 1) div 2;
    }

    # Linear interpolation, then clamp, then optionally invert.
    my $frac = ($value - $!min) / ($!max - $!min);
    my Int $cell = ($frac * ($!cells - 1)).round.Int;
    $cell = 0          if $cell < 0;
    $cell = $!cells - 1 if $cell >= $!cells;
    $cell = ($!cells - 1) - $cell if $!invert;
    $cell.UInt;
}

#|( Map a cell index back to its midpoint value in the domain.
    Out-of-range cell indices are clamped. )
method cell-to-value(Int $cell-in --> Real) {
    return $!min if $!min == $!max;
    return $!min if $!cells == 1;

    my Int $cell = $cell-in;
    $cell = 0          if $cell < 0;
    $cell = $!cells - 1 if $cell >= $!cells;
    $cell = ($!cells - 1) - $cell if $!invert;

    ($cell / ($!cells - 1)) * ($!max - $!min) + $!min;
}
