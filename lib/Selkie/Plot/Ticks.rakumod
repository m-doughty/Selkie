=begin pod

=head1 NAME

Selkie::Plot::Ticks - Heckbert "nice-number" tick generation for axes

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Plot::Ticks;

# Roughly five ticks across [0, 100]. Heckbert lands on step=20 (the
# nearest "nice" multiplier in {1, 2, 5}); five ticks would have
# wanted step=25, which isn't in the set, so we get six instead.
my $t = Selkie::Plot::Ticks.nice(min => 0, max => 100, count => 5);
$t.values;     # → (0, 20, 40, 60, 80, 100)
$t.labels;     # → ("0", "20", "40", "60", "80", "100")
$t.step;       # → 20

# Awkward endpoints — Heckbert pads to nice numbers
my $u = Selkie::Plot::Ticks.nice(min => 7, max => 93, count => 5);
$u.values;     # → (0, 20, 40, 60, 80, 100)  — extends past min/max
$u.step;       # → 20

# Sub-unit ranges produce sub-unit steps
my $v = Selkie::Plot::Ticks.nice(min => 0, max => 1, count => 5);
$v.values;     # → (0, 0.2, 0.4, 0.6, 0.8, 1.0)
$v.labels;     # → ("0.0", "0.2", "0.4", "0.6", "0.8", "1.0")
$v.step;       # → 0.2

=end code

=head1 DESCRIPTION

C<Selkie::Plot::Ticks> picks "nice" tick values for an axis covering
the domain C<[min, max]>. Nice means each tick is a multiple of
C<step>, and C<step> is chosen from C<{1, 2, 5} × 10^n> for some
integer C<n> — the values that humans naturally read on a graph.

The algorithm is Paul Heckbert's classic, described in I<Graphics
Gems> (1990): pick a "nice" range, divide it into roughly C<count>
intervals, snap the interval to a nice number, then enumerate ticks.
The output count is I<approximately> C<count>, not exactly — typical
deviation is ±1 tick.

=head2 The algorithm

Given C<min>, C<max>, and a target C<count>:

=item Compute C<range = max - min> and snap it up to a nice number (floored to a 1, 2, 5, or 10 leading digit).
=item Compute C<rough-step = range / (count - 1)> and snap it I<rounded> to a nice number — small differences in C<rough-step> shouldn't bump the leading digit if either side is reasonable.
=item Compute C<nice-min = floor(min / step) * step> and C<nice-max = ceil(max / step) * step> — round the data range outward to the nearest tick.
=item Enumerate ticks at C<nice-min, nice-min + step, nice-min + 2·step, ..., nice-max>.

The result is a tick set whose endpoints I<may extend slightly beyond>
the data range. This is intentional — chart axes look better when the
labels are round numbers like C<0> and C<100> rather than the precise
data extent of C<7> and C<93>.

=head2 A worked example

For C<min = 0.001>, C<max = 0.009>, C<count = 4>:

=item C<range = nice(0.008, :!round)>. C<0.008 / 10^-3 = 8> → leading digit 10 → range = C<0.01>.
=item C<rough-step = 0.01 / 3 ≈ 0.00333>. C<nice(0.00333, :round)>: C<3.33 / 10^-3 = 3.33> → leading digit 5 → step = C<0.005>.
=item C<nice-min = floor(0.001 / 0.005) * 0.005 = 0>. C<nice-max = ceil(0.009 / 0.005) * 0.005 = 0.01>.
=item Ticks: C<0, 0.005, 0.01> — three ticks, requested four. Heckbert prefers nice spacing over exact count.

=head2 Edge cases

=item B<C<count E<lt> 2>> — nonsensical (a single tick has no spacing). Throws.
=item B<C<min E<gt> max>> — throws. Pass arguments in order.
=item B<C<min == max>> — degenerate. Returns a single-element tick set at C<min>; C<step> is C<0>.

=head1 EXAMPLES

=head2 Driving an axis widget

=begin code :lang<raku>

use Selkie::Plot::Scaler;
use Selkie::Plot::Ticks;
use Selkie::Widget::Axis;

my $scaler = Selkie::Plot::Scaler.linear(min => 0, max => 1000, cells => 80);
my $ticks  = Selkie::Plot::Ticks.nice(min => 0, max => 1000, count => 5);

my $axis = Selkie::Widget::Axis.new(
    edge   => 'bottom',
    :$scaler,
    :$ticks,
);

=end code

=head2 Picking labels for a sub-unit range

When the step is fractional, labels are zero-padded to the step's
precision so they align visually:

=begin code :lang<raku>

my $t = Selkie::Plot::Ticks.nice(min => 0.0, max => 0.1, count => 5);
$t.step;       # → 0.02
$t.labels;     # → ("0.00", "0.02", "0.04", "0.06", "0.08", "0.10")

=end code

=head1 SEE ALSO

=item L<Selkie::Plot::Scaler> — maps tick values to cell positions
=item L<Selkie::Widget::Axis> — renders ticks + labels along an edge

=end pod

unit class Selkie::Plot::Ticks;

#| The data-range lower bound passed in.
has Real $.min;

#| The data-range upper bound passed in.
has Real $.max;

#| The target tick count (approximate; actual may differ by ±1-2).
has UInt $.count;

#| The chosen tick step. Always a member of C<{1, 2, 5} × 10^n>. Zero
#| in the degenerate C<min == max> case.
has Real $.step;

#| The generated tick values, in ascending order.
has Real @.values;

#|( Generate a nice tick set covering C<[min, max]> with approximately
    C<count> ticks. The actual count may differ from C<count> by ±1-2
    — Heckbert prefers round numbers over an exact count.

    Throws if C<count E<lt> 2> or if C<min E<gt> max>. C<min == max> is
    permitted (returns a single-tick set). )
method nice(::?CLASS:U:
            Real :$min!,
            Real :$max!,
            UInt :$count = 5,
            --> ::?CLASS) {
    die "Selkie::Plot::Ticks.nice: count must be >= 2 (got $count)"
        if $count < 2;
    die "Selkie::Plot::Ticks.nice: min ($min) must be <= max ($max)"
        if $min > $max;

    if $min == $max {
        return self.bless(:$min, :$max, :$count, step => 0, values => ($min,));
    }

    my $range = nice-num($max - $min, :!round);
    my $step  = nice-num($range / ($count - 1), :round);

    my $nice-min = ($min / $step).floor * $step;
    my $nice-max = ($max / $step).ceiling * $step;

    my @values;
    # FP tolerance: we accumulate by adding $step in a loop; tiny drift
    # can push the loop bound just over $nice-max. Adding step/2
    # tolerance is the standard guard.
    my $v = $nice-min;
    while $v <= $nice-max + $step / 2 {
        @values.push: round-to-step($v, $step);
        $v += $step;
    }

    self.bless(:$min, :$max, :$count, :$step, :@values);
}

#|( Return the tick values as a list. Same data as the C<values>
    accessor; this method exists for API symmetry with C<labels>. )
method values(--> List) { @!values.list }

#|( Return formatted labels for each tick. Labels use a fixed
    decimal precision derived from C<step> so they align visually:

    =item Integer step (e.g. 25) → no decimals: C<("0", "25", "50")>
    =item Sub-unit step (e.g. 0.005) → decimals matching the step: C<("0.000", "0.005", "0.010")>

    Negative ticks render with a leading minus sign. )
method labels(--> List) {
    my $decimals = decimals-for($!step);
    @!values.map({ sprintf("%.{$decimals}f", $_) }).list;
}

# === Heckbert helpers ===

# Round a value to the cleanest representation for a given step. The
# value is generated by floating-point accumulation, so it can drift
# from the exact tick (0.30000000000000004 instead of 0.3). Round to
# the step's precision to remove drift.
sub round-to-step(Real $v, Real $step --> Real) {
    return $v if $step == 0;
    my $decimals = decimals-for($step);
    return $v if $decimals == 0 && $step.Int == $step;
    my $factor = 10 ** $decimals;
    ($v * $factor).round / $factor;
}

# Number of decimal places needed to faithfully render a value of this
# step. Integer steps need 0 decimals; sub-unit steps need enough to
# show the smallest digit (0.005 → 3, 0.25 → 2, 2.5 → 1).
sub decimals-for(Real $step --> Int) {
    return 0 if $step == 0;
    my $abs = $step.abs;
    return 0 if $abs >= 1 && $abs.Int == $abs;
    my $exp = $abs.log(10).floor;
    # For 2.5: exp = 0, but it has 1 decimal. For 0.5: exp = -1, 1
    # decimal. For 0.25: exp = -1, but needs 2 decimals. The exponent
    # alone undercounts when the step has more digits than its leading
    # magnitude. Take the max of -exp and the actual decimal count.
    my $scientific = $abs.fmt('%g');
    my $decimal-count = 0;
    if $scientific ~~ /'.' (\d+)/ {
        $decimal-count = $0.chars;
    }
    max(-$exp, $decimal-count, 0);
}

# Heckbert's "nice number" — snap a value to the nearest member of
# {1, 2, 5, 10} × 10^n. With C<:round>, snap to the nearest; without,
# snap up to the nearest. The :round variant is used for the step
# (nudges in either direction shouldn't bump the leading digit); the
# :!round variant is used for the range (always pad outward).
sub nice-num(Real $x, Bool :$round = False --> Real) {
    return 0 if $x == 0;
    my $abs = $x.abs;
    my $exp = $abs.log(10).floor;
    my $f = $abs / 10 ** $exp;
    my $nf;
    if $round {
        $nf = $f < 1.5 ?? 1 !! $f < 3 ?? 2 !! $f < 7 ?? 5 !! 10;
    } else {
        $nf = $f <= 1 ?? 1 !! $f <= 2 ?? 2 !! $f <= 5 ?? 5 !! 10;
    }
    my $signed = $nf * 10 ** $exp * ($x < 0 ?? -1 !! 1);
    $signed;
}
