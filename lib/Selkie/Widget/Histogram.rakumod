=begin pod

=head1 NAME

Selkie::Widget::Histogram - Bin a numeric series and render it as a BarChart

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Histogram;
use Selkie::Sizing;

# Bin 1000 random samples into 10 bins
my @samples = (1..1000).map: { rand * 100 };
my $h = Selkie::Widget::Histogram.new(
    values => @samples,
    bins   => 10,
    sizing => Sizing.flex,
);

# Custom bin edges instead of equal-width bins
my $edges = Selkie::Widget::Histogram.new(
    values    => @latencies-ms,
    bin-edges => [0, 10, 50, 100, 500, 1000, 5000],
    sizing    => Sizing.flex,
);

=end code

=head1 DESCRIPTION

A histogram is a categorical view of a numeric distribution. This
widget bins a list of numeric values into intervals and delegates
rendering to L<Selkie::Widget::BarChart>. Each bin becomes a bar
labelled by its lower edge.

=head2 Bin convention

Intervals are B<left-closed, right-open>, with the final bin
B<closed-closed> so the maximum sample is always counted. For bin
edges C<[0, 10, 20, 30]>:

=item Bin 1: C<[0, 10)> — values 0 ≤ v < 10
=item Bin 2: C<[10, 20)>
=item Bin 3: C<[20, 30]> — values 20 ≤ v ≤ 30 (inclusive)

This matches numpy / R / matplotlib defaults.

=head2 Modes

Two ways to specify the bins:

=item B<Equal-width> — pass C<:bins(N)>. The widget computes N equal-width bins spanning C<[min, max]> of the data.
=item B<Explicit edges> — pass C<:bin-edges([...])>. The widget uses your edges directly. C<edges.elems> = bin count + 1.

The two are mutually exclusive. C<:bins> is convenient; C<:bin-edges>
is for non-uniform binning (log-scale latency, age brackets, etc.).

=head1 EXAMPLES

=head2 Distribution of request latencies

=begin code :lang<raku>

my @latencies = $request-log.map: *.<duration-ms>;
my $h = Selkie::Widget::Histogram.new(
    values => @latencies,
    bins   => 20,
    sizing => Sizing.flex,
);

=end code

=head2 Non-uniform bins for skewed data

Latencies cluster near zero with a long tail. Equal bins waste most
of the chart on near-zero values. Custom edges let you focus on the
distribution where it matters:

=begin code :lang<raku>

my $h = Selkie::Widget::Histogram.new(
    values    => @latencies,
    bin-edges => [0, 5, 10, 25, 50, 100, 250, 500, 1000, 5000],
    sizing    => Sizing.flex,
);

=end code

=head2 Reactive — auto-rebin when the source data changes

=begin code :lang<raku>

# Histogram doesn't bind to a store directly; instead, subscribe in
# app code and call set-values when the source updates.
$store.subscribe-with-callback(
    'latencies-hist',
    -> $s { $s.get-in('metrics', 'latency-samples') // [] },
    -> @samples { $hist.set-values(@samples) },
    $hist,
);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::BarChart> — the bar renderer this delegates to
=item L<Selkie::Plot::Ticks> — for picking nice bin edges manually

=end pod

use Selkie::Widget::BarChart;

unit class Selkie::Widget::Histogram is Selkie::Widget::BarChart;

#| Numeric values to bin.
has Real @.values;

#| Equal-width bin count. Mutually exclusive with C<bin-edges>.
has UInt $.bins = 0;

#| Explicit bin edges, ascending. C<bin-edges.elems> = bin count + 1.
#| Mutually exclusive with C<bins>.
has Real @.bin-edges;

submethod TWEAK {
    die "Selkie::Widget::Histogram: pass exactly one of :bins or :bin-edges"
        if ($!bins > 0 && @!bin-edges.elems > 0)
        || ($!bins == 0 && @!bin-edges.elems == 0);
    die "Selkie::Widget::Histogram: bin-edges must be ascending"
        if @!bin-edges.elems > 0
            && @!bin-edges.list ne @!bin-edges.sort.list;

    self!rebin;
}

#|( Replace the value list and re-bin. The chart re-renders
    automatically. )
method set-values(@new) {
    @!values = @new;
    self!rebin;
    self.mark-dirty;
}

method !rebin() {
    my @data;
    if $!bins > 0 {
        @data = self!bin-equal-width;
    } else {
        @data = self!bin-edges;
    }
    # Cast through the parent's data attribute. We use direct attribute
    # access because BarChart's set-data has a guard against
    # store-path mode that doesn't apply here.
    nextwith(:@data) if False;          # silence "no proto" — never runs
    # The right way: assign to the inherited @.data attribute.
    self.set-data(@data);
}

method !bin-equal-width(--> List) {
    return () if @!values.elems == 0;
    my @clean = @!values.grep({ .defined && $_ !=== NaN });
    return () if @clean.elems == 0;

    my $lo = @clean.min;
    my $hi = @clean.max;
    if $lo == $hi {
        # All samples identical — single bin
        return (
            { label => $lo.fmt('%g'), value => @clean.elems },
        ).list;
    }

    my $width = ($hi - $lo) / $!bins;
    my @counts = 0 xx $!bins;
    for @clean -> $v {
        my $idx = (($v - $lo) / $width).Int;
        $idx = $!bins - 1 if $idx >= $!bins;     # max value falls into last bin
        $idx = 0          if $idx < 0;
        @counts[$idx]++;
    }

    my @data;
    for ^$!bins -> $i {
        my $edge-lo = $lo + $i * $width;
        @data.push: {
            label => $edge-lo.fmt('%g'),
            value => @counts[$i],
        };
    }
    @data;
}

method !bin-edges(--> List) {
    return () if @!values.elems == 0 || @!bin-edges.elems < 2;
    my @clean = @!values.grep({ .defined && $_ !=== NaN });
    return () if @clean.elems == 0;

    my $bins = @!bin-edges.elems - 1;
    my @counts = 0 xx $bins;

    for @clean -> $v {
        # Left-closed / right-open, except the last bin which is
        # closed-closed (so the max value is always counted).
        my $found = False;
        for ^$bins -> $i {
            my $edge-lo = @!bin-edges[$i];
            my $edge-hi = @!bin-edges[$i + 1];
            my $in-bin = $i == $bins - 1
                ?? ($v >= $edge-lo && $v <= $edge-hi)
                !! ($v >= $edge-lo && $v <  $edge-hi);
            if $in-bin {
                @counts[$i]++;
                $found = True;
                last;
            }
        }
        # Values outside [first-edge, last-edge] are dropped silently
        # — same as numpy.histogram default behaviour.
    }

    my @data;
    for ^$bins -> $i {
        @data.push: {
            label => @!bin-edges[$i].fmt('%g'),
            value => @counts[$i],
        };
    }
    @data;
}
