=begin pod

=head1 NAME

Selkie::Plot::Palette - Colorblind-friendly series palettes and color ramps for chart widgets

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Plot::Palette;

# Series palettes — discrete colors for multi-series charts
my @colors = Selkie::Plot::Palette.series('okabe-ito');
# (0xE69F00, 0x56B4E9, 0x009E73, 0xF0E442, 0x0072B2,
#  0xD55E00, 0xCC79A7, 0x999999)

# Color ramps — continuous gradients for heatmaps
my @stops = Selkie::Plot::Palette.ramp('viridis');
# (0.0 => 0x440154, 0.25 => 0x3B528B, 0.5 => 0x21908C, ...)

# Sample a ramp at any position in [0, 1]
my $color = Selkie::Plot::Palette.sample('viridis', 0.42);
# → 0x2E6A8E (interpolated between 0.25 and 0.5 stops)

=end code

=head1 DESCRIPTION

Two abstractions for chart colors:

=item B<Series palettes> — discrete lists of distinct colors for
multi-series charts (BarChart with N categories, LineChart with N
series). Defaults to L<Okabe-Ito|https://jfly.uni-koeln.de/color/>,
designed to be distinguishable for the most common forms of
colorblindness.

=item B<Color ramps> — continuous gradients sampled by a normalised
position in C<[0, 1]>, for heatmaps and other value-encoded color use.
Defaults to L<viridis|https://bids.github.io/colormap/>, the
perceptually uniform colormap that's been the matplotlib default
since 2.0.

Both are I<separate from> L<Selkie::Theme>. Theme slots cover named
chart elements (axis, gridlines, legend background); palettes cover
data colors. Different access patterns, different homes.

=head2 Series palettes

=item C<okabe-ito> (default, 8 colors) — Okabe & Ito's palette,
optimised for deuteranopia / protanopia / tritanopia. The original
palette starts with pure black, which is invisible on dark
backgrounds; this implementation substitutes C<0x999999> as the first
color so the palette works on either light or dark themes.

=item C<tol-bright> (7 colors) — Paul Tol's "bright" qualitative
palette (L<personal.sron.nl/~pault|https://personal.sron.nl/~pault/>).
Higher saturation, also colorblind-safe.

=item C<tableau-10> (10 colors) — Tableau's category10 palette.
Vivid and well-tested in business dashboards. Less colorblind-friendly
than Okabe-Ito but maximises distinct hues for many series.

If a chart needs more series than its palette provides, the colors
cycle. For more than ~8 series consider redesigning the chart
(faceting, stacked layout, on-hover series isolation) — at a glance,
the human eye can't reliably distinguish more than ~7 chart series by
color alone.

=head2 Color ramps

All ramps are 5-stop. Sampling between stops uses straight linear
interpolation in RGB space — perceptually correct interpolation would
need OkLab or Lab conversion, which is overkill for terminal cells
where adjacent values blur visually anyway.

=item C<viridis> (default for heatmaps) — perceptually uniform,
colorblind-safe, prints reasonably in greyscale. The matplotlib
default since 2.0.
=item C<magma> — like viridis but warmer (purple → red → cream).
=item C<plasma> — high-saturation gradient (deep blue → pink → orange).
=item C<coolwarm> — diverging blue→white→red, useful for signed data
where 0 is special (correlations, deltas).
=item C<grayscale> — five steps of gray. Mostly for accessibility
fallback or print contexts.

=head1 EXAMPLES

=head2 Coloring a multi-series LineChart

=begin code :lang<raku>

my @palette = Selkie::Plot::Palette.series('okabe-ito');
my @series = (
    { label => 'cpu',     values => @cpu,    color => @palette[0] },
    { label => 'memory',  values => @mem,    color => @palette[1] },
    { label => 'iowait',  values => @iowait, color => @palette[2] },
);

my $chart = Selkie::Widget::LineChart.new(:@series, :show-legend);

=end code

=head2 Driving a Heatmap with a custom ramp stop

=begin code :lang<raku>

my $heatmap = Selkie::Widget::Heatmap.new(
    data => @grid,
    ramp => 'coolwarm',
);

# Or, for one-off color lookups in custom widget code:
my $color = Selkie::Plot::Palette.sample('viridis', $normalised-value);

=end code

=head2 Cycling a palette beyond its length

=begin code :lang<raku>

my @palette = Selkie::Plot::Palette.series('tol-bright');   # 7 colors
my $color-for = sub ($i) { @palette[$i mod @palette.elems] };

# Series 0..6 get distinct colors; 7 wraps to series 0's color.

=end code

=head1 SEE ALSO

=item L<Selkie::Plot::Scaler> — value→cell mapping
=item L<Selkie::Plot::Ticks> — nice-number axis labels
=item L<Selkie::Theme> — chart-element styling slots (axis, legend bg, etc.)

=end pod

unit class Selkie::Plot::Palette;

# === Series palettes ===
#
# Discrete colors for multi-series charts. All values are 24-bit RGB
# integers (0xRRGGBB), as expected by Selkie::Style.

# Okabe & Ito's colorblind-safe qualitative palette. Original first
# entry was 0x000000 (pure black) which is invisible against dark
# backgrounds; substituted with 0x999999 for theme-agnostic use.
# Reference: https://jfly.uni-koeln.de/color/
my @OKABE-ITO = (
    0x999999,   # gray (substituted from black)
    0xE69F00,   # orange
    0x56B4E9,   # sky blue
    0x009E73,   # bluish green
    0xF0E442,   # yellow
    0x0072B2,   # blue
    0xD55E00,   # vermillion
    0xCC79A7,   # reddish purple
);

# Paul Tol's "bright" qualitative palette.
# Reference: https://personal.sron.nl/~pault/
my @TOL-BRIGHT = (
    0x4477AA,   # blue
    0x66CCEE,   # cyan
    0x228833,   # green
    0xCCBB44,   # yellow
    0xEE6677,   # red
    0xAA3377,   # purple
    0xBBBBBB,   # gray
);

# Tableau's category10 palette.
my @TABLEAU10 = (
    0x4E79A7,   # blue
    0xF28E2B,   # orange
    0xE15759,   # red
    0x76B7B2,   # teal
    0x59A14F,   # green
    0xEDC948,   # yellow
    0xB07AA1,   # purple
    0xFF9DA7,   # pink
    0x9C755F,   # brown
    0xBAB0AC,   # gray
);

my %SERIES-PALETTES =
    'okabe-ito'  => @OKABE-ITO,
    'tol-bright' => @TOL-BRIGHT,
    'tableau-10' => @TABLEAU10,
;

# === Color ramps ===
#
# 5-stop continuous gradients keyed by normalised position 0..1.
# Stops are stored as ordered lists of Pairs so we can binary-search
# by position.

# Viridis — perceptually uniform, the matplotlib default since 2.0.
# Stops sampled at 0/0.25/0.5/0.75/1 from the canonical 256-step LUT.
my @VIRIDIS = (
    0.00 => 0x440154,
    0.25 => 0x3B528B,
    0.50 => 0x21908C,
    0.75 => 0x5DC863,
    1.00 => 0xFDE725,
);

# Magma — purple → magenta → cream, complements viridis.
my @MAGMA = (
    0.00 => 0x000004,
    0.25 => 0x3B0F70,
    0.50 => 0x8C2981,
    0.75 => 0xDE4968,
    1.00 => 0xFCFDBF,
);

# Plasma — deep blue → magenta → orange, more saturated than viridis.
my @PLASMA = (
    0.00 => 0x0D0887,
    0.25 => 0x6A00A8,
    0.50 => 0xB12A90,
    0.75 => 0xE16462,
    1.00 => 0xFCA636,
);

# Coolwarm — blue → white → red diverging, useful for signed data.
my @COOLWARM = (
    0.00 => 0x3B4CC0,
    0.25 => 0x6688EE,
    0.50 => 0xDDDDDD,
    0.75 => 0xEE8866,
    1.00 => 0xB40426,
);

# Grayscale — dark to light, for accessibility / print fallback.
my @GRAYSCALE = (
    0.00 => 0x101010,
    0.25 => 0x404040,
    0.50 => 0x808080,
    0.75 => 0xC0C0C0,
    1.00 => 0xF0F0F0,
);

my %RAMPS =
    'viridis'   => @VIRIDIS,
    'magma'     => @MAGMA,
    'plasma'    => @PLASMA,
    'coolwarm'  => @COOLWARM,
    'grayscale' => @GRAYSCALE,
;

#|( Return the named series palette as a list of 24-bit RGB integers.
    Defaults to C<okabe-ito>. Throws on unknown names. )
method series(::?CLASS:U: Str:D $name = 'okabe-ito' --> List) {
    %SERIES-PALETTES{$name}
        or die "Selkie::Plot::Palette.series: unknown palette '$name'."
            ~ " Known: {%SERIES-PALETTES.keys.sort.join(', ')}";
    %SERIES-PALETTES{$name}.list;
}

#|( Return the named color ramp as a list of C<Real => UInt> Pairs,
    each pair being a position in C<[0, 1]> mapped to a 24-bit RGB.
    Defaults to C<viridis>. Throws on unknown names. )
method ramp(::?CLASS:U: Str:D $name = 'viridis' --> List) {
    %RAMPS{$name}
        or die "Selkie::Plot::Palette.ramp: unknown ramp '$name'."
            ~ " Known: {%RAMPS.keys.sort.join(', ')}";
    %RAMPS{$name}.list;
}

#|( Sample a ramp at C<$t ∈ [0, 1]>, returning the interpolated
    24-bit RGB color. Out-of-range C<$t> is clamped. Interpolation is
    linear in RGB space (not OkLab) — adequate for terminal cells. )
method sample(::?CLASS:U: Str:D $name, Real $t --> UInt) {
    my @stops = self.ramp($name);
    my $clamped = ($t max 0.0) min 1.0;

    # Trivial case: hit a stop exactly.
    for @stops -> $stop {
        return $stop.value.UInt if $stop.key == $clamped;
    }

    # Find the bracketing pair and lerp.
    for ^(@stops.elems - 1) -> $i {
        my $lo = @stops[$i];
        my $hi = @stops[$i + 1];
        if $clamped > $lo.key && $clamped < $hi.key {
            my $local-t = ($clamped - $lo.key) / ($hi.key - $lo.key);
            return lerp-rgb($lo.value, $hi.value, $local-t);
        }
    }

    # Defensive — clamp guarantees $t ∈ [0, 1] which is covered above.
    @stops[*-1].value.UInt;
}

# Linear interpolate two 24-bit RGB colors, channel-wise.
sub lerp-rgb(UInt $a, UInt $b, Real $t --> UInt) {
    my $ar = ($a +> 16) +& 0xFF;
    my $ag = ($a +> 8)  +& 0xFF;
    my $ab =  $a        +& 0xFF;
    my $br = ($b +> 16) +& 0xFF;
    my $bg = ($b +> 8)  +& 0xFF;
    my $bb =  $b        +& 0xFF;

    my $r = ($ar * (1 - $t) + $br * $t).round.Int;
    my $g = ($ag * (1 - $t) + $bg * $t).round.Int;
    my $bo = ($ab * (1 - $t) + $bb * $t).round.Int;

    (($r +< 16) +| ($g +< 8) +| $bo).UInt;
}
