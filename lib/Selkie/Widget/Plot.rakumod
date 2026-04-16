=begin pod

=head1 NAME

Selkie::Widget::Plot - Streaming chart wrapping notcurses' native ncuplot/ncdplot

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Plot;
use Selkie::Sizing;

# Streaming uint plot — push samples as they arrive
my $cpu = Selkie::Widget::Plot.new(
    type     => 'uint',
    min-y    => 0,
    max-y    => 100,
    title    => 'CPU %',
    sizing   => Sizing.flex,
);

$cpu-supply.tap: -> $sample-pct {
    state $tick = 0;
    $cpu.push-sample($tick++, $sample-pct);
};

# Streaming double plot for fractional / non-integer measurements
my $temp = Selkie::Widget::Plot.new(
    type    => 'double',
    min-y   => -10.0,
    max-y   => 40.0,
    sizing  => Sizing.flex,
);

# Reactive — bind to a store array of (x, y) pairs and the widget
# will pick up new samples from store updates.
my $bound = Selkie::Widget::Plot.new(
    store-path => <metrics throughput>,
    type       => 'uint',
    min-y      => 0,
    max-y      => 1000,
    sizing     => Sizing.flex,
);

=end code

=head1 DESCRIPTION

C<Selkie::Widget::Plot> wraps notcurses' built-in plot widgets:
C<ncuplot> (uint64 samples) and C<ncdplot> (num64 samples). The
native code handles scaling, tick marks, blitter selection, and
incremental rendering — this widget's job is lifecycle management
(creating and destroying the native handle, surviving plane
resizes), the Selkie sample-push API, and optional store binding.

The plot is B<streaming-oriented>: you push samples one at a time
and it maintains a ring buffer of recent samples internally. For
fixed/static data plotted with full chart machinery (axes, legends,
multi-series), use L<Selkie::Widget::LineChart> instead. For an
inline single-row chart, use L<Selkie::Widget::Sparkline>.

=head2 The two type variants

=item B<uint> (default) — wraps C<ncuplot_*>. Y values are C<uint64>. Pass C<:type<uint>>.
=item B<double> — wraps C<ncdplot_*>. Y values are C<num64>. Pass C<:type<double>> for fractional measurements.

X values are always C<uint64> in both variants — they're slot
indices, not arbitrary numeric values. If you need a non-monotonic
or floating-point x-axis, use L<Selkie::Widget::LineChart> or
L<Selkie::Widget::ScatterPlot>.

=head2 Native handle lifecycle

The native ncuplot / ncdplot handle is created lazily on the first
C<render()> after the widget gets a plane. It survives until one of:

=item B<resize> — the handle is destroyed and a new one is created at the new dimensions. B<Existing samples are lost.> notcurses' plot API exposes no way to transfer sample state across resize. If you need history that survives terminal resize, keep the sample buffer outside the widget (e.g. in the store) and use L<Selkie::Widget::LineChart> with reactive binding instead.
=item B<park> — when scrolled off-screen by a container swap, the handle is destroyed proactively. Recreated on the next render.
=item B<destroy> — final cleanup at widget shutdown.

Samples pushed before the handle exists (e.g. between widget
construction and first plane attach) are buffered and flushed to
the handle when it's created.

=head2 Reactive binding

C<:store-path> binds the widget to a store path holding a list of
C<($x, $y)> pairs. On dirty (when the store updates), the widget
diffs the new list against its last-pushed-index and forwards new
samples to the native handle. Truncating the array (or replacing
it with a shorter one) causes the widget to recreate the handle and
re-push from scratch.

=head1 EXAMPLES

=head2 Plotting an interval-driven sine wave

=begin code :lang<raku>

use Selkie::Widget::Plot;

my $plot = Selkie::Widget::Plot.new(
    type   => 'double',
    min-y  => -1.0,
    max-y  => 1.0,
    sizing => Sizing.flex,
);

# Drive samples from an interval Supply
react {
    whenever Supply.interval(0.05) -> $i {
        my $value = sin($i * 0.1);
        $plot.push-sample($i, $value);
    }
}

=end code

=head2 Lifecycle and resize behavior

The handle automatically recreates on resize. Sample history is lost,
which is fine for a streaming dashboard but might surprise you in
testing:

=begin code :lang<raku>

my $plot = Selkie::Widget::Plot.new(:type<uint>, :min-y(0), :max-y(100));
$plot.push-sample(0, 50);
$plot.push-sample(1, 75);

# Simulate a terminal resize:
$plot.handle-resize(20, 80);

# At this point the previous samples are gone — the handle was
# recreated at the new dimensions. To preserve history, keep the
# sample buffer in your app code (or the store) and re-push after
# resize. For a chart that survives resize without manual
# bookkeeping, use Selkie::Widget::LineChart instead.

=end code

=head2 Disabling spesh in test code

The shared notcurses + native plot interaction trips the MoarVM
specializer in some pathological cases. The snapshot harness sets
C<MVM_SPESH_DISABLE=1> globally; in your own test code that exercises
the Plot widget's lifecycle, set the env var before running. See
C<xt/snapshots/25-plot-streaming.raku> for a working example.

=head1 SEE ALSO

=item L<Selkie::Widget::Sparkline> — single-row inline chart, no native handle
=item L<Selkie::Widget::LineChart> — full multi-series chart for static data
=item L<Selkie::Plot::Scaler>

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Widgets;

use Selkie::Widget;

unit class Selkie::Widget::Plot does Selkie::Widget;

constant PLOT-TYPE-UINT   = 'uint';
constant PLOT-TYPE-DOUBLE = 'double';

#| Sample type variant: C<uint> (default) wraps C<ncuplot>, C<double>
#| wraps C<ncdplot>.
has Str $.type = PLOT-TYPE-UINT;

#| Lower bound of the Y range. Below this, samples saturate to the
#| bottom of the plot.
has Real $.min-y = 0;

#| Upper bound of the Y range. Above this, samples saturate to the
#| top of the plot.
has Real $.max-y = 100;

#| Optional title written above the plot by notcurses.
has Str $.title;

#| Notcurses blitter for the plot rendering. Defaults to braille
#| (2×4 sub-cell resolution); see C<NCBLIT_*> in
#| C<Notcurses::Native::Types>.
has Int $.gridtype = NCBLIT_BRAILLE;

#| Number of x-axis slots in the ring buffer. Defaults to widget
#| width × 2 so braille's sub-cell density is fully used. Set
#| explicitly when pushing more than one sample per cell-column.
has UInt $.rangex = 0;

#| Optional reactive binding — store path to a list of C<($x, $y)>
#| pairs. The widget pushes new samples to the native handle when
#| the store path updates.
has Str @.store-path;

#| Message rendered when no samples have been received yet. The
#| default is the expected startup state for monitoring dashboards.
#| Set to the empty string to suppress (the plot will show a blank
#| pane until the first sample arrives).
has Str $.empty-message = 'No data';

# Internal state
has $!plot;                 # NcuplotHandle | NcdplotHandle | Nil
has @!buffered-samples;     # samples queued before handle exists
has Int $!last-pushed-idx = -1;     # for store-path mode
has Bool $!has-samples = False;     # flips True once any sample is pushed

submethod TWEAK {
    die "Selkie::Widget::Plot: type must be 'uint' or 'double' (got '$!type')"
        unless $!type eq PLOT-TYPE-UINT|PLOT-TYPE-DOUBLE;
    die "Selkie::Widget::Plot: min-y ({$!min-y}) must be < max-y ({$!max-y})"
        unless $!min-y < $!max-y;
}

method on-store-attached($store) {
    return unless @!store-path.elems > 0;
    self.once-subscribe(
        'plot-' ~ self.widget-id,
        |@!store-path,
    );
}

#|( Push a sample. C<$x> is the slot index (always integer); C<$y>
    is the value (UInt for type=uint, Num for type=double).

    If the native handle doesn't exist yet (before plane attach or
    immediately after resize), the sample is buffered and flushed on
    next render. )
method push-sample(Int(Cool) $x, Real $y) {
    if $!plot.defined {
        self!push-to-handle($x, $y);
    } else {
        @!buffered-samples.push: ($x, $y);
    }
    $!has-samples = True;
    self.mark-dirty;
}

#|( Set (overwrite) the sample at slot C<$x>. Same semantics as
    notcurses' C<ncuplot_set_sample> / C<ncdplot_set_sample>:
    replaces rather than accumulating. No-op if the handle hasn't
    been created yet — use C<push-sample> for buffer-aware writes. )
method set-sample(Int(Cool) $x, Real $y) {
    return unless $!plot.defined;
    if $!type eq PLOT-TYPE-UINT {
        ncuplot_set_sample($!plot, $x.UInt, $y.UInt);
    } else {
        ncdplot_set_sample($!plot, $x.UInt, $y.Num);
    }
    self.mark-dirty;
}

method !push-to-handle(Int $x, Real $y) {
    return if $y === NaN;       # ncuplot/ncdplot can't represent NaN
    if $!type eq PLOT-TYPE-UINT {
        ncuplot_add_sample($!plot, $x.UInt, $y.UInt);
    } else {
        ncdplot_add_sample($!plot, $x.UInt, $y.Num);
    }
    $!has-samples = True;
}

method !ensure-handle() {
    return if $!plot.defined;
    return without self.plane;
    return if self.rows == 0 || self.cols == 0;

    # Pick a default rangex if the user didn't override.
    my $rangex = $!rangex > 0 ?? $!rangex !! self.cols * 2;

    # NcplotOptions: title goes through the multi-method when set so
    # the C string is allocated correctly.
    my $opts = $!title.defined
        ?? NcplotOptions.new(:title($!title), :gridtype($!gridtype), :$rangex)
        !! NcplotOptions.new(:gridtype($!gridtype), :$rangex);

    # The plot adopts the plane it's created with — we must give it
    # a sub-plane (not our widget's main plane) so destroying the
    # plot doesn't take our widget's plane with it.
    my $sub-opts = NcplaneOptions.new(:y(0), :x(0), :rows(self.rows), :cols(self.cols));
    my $sub-plane = ncplane_create(self.plane, $sub-opts);
    return without $sub-plane;

    if $!type eq PLOT-TYPE-UINT {
        $!plot = ncuplot_create($sub-plane, $opts,
                                $!min-y.UInt, $!max-y.UInt);
    } else {
        $!plot = ncdplot_create($sub-plane, $opts,
                                $!min-y.Num, $!max-y.Num);
    }

    return without $!plot.defined;

    # Flush samples that were pushed before the handle existed.
    for @!buffered-samples -> ($x, $y) {
        self!push-to-handle($x, $y);
    }
    @!buffered-samples = ();
}

method !destroy-handle() {
    return unless $!plot.defined;
    if $!type eq PLOT-TYPE-UINT {
        ncuplot_destroy($!plot);
    } else {
        ncdplot_destroy($!plot);
    }
    $!plot = Nil;
    # ncuplot_destroy takes the sub-plane with it — do not separately
    # destroy the sub-plane.
    $!last-pushed-idx = -1;
}

method render() {
    return without self.plane;

    # Always erase the widget's main plane first. The native ncuplot
    # renders into a sub-plane (created in !ensure-handle), but that
    # sub-plane only covers the cells the plot actually draws into —
    # any leftover text from a previous empty-state render would
    # remain visible behind it. Erasing every frame guarantees a
    # clean canvas before we either show the "no data" placeholder
    # or hand off to ncuplot.
    ncplane_erase(self.plane);

    # When the widget has no samples yet (the expected startup state
    # in monitoring apps), show a placeholder message on our own
    # plane. The moment any sample is pushed we create the native
    # handle and hand rendering over to notcurses.
    if !$!has-samples {
        self!render-empty;
        self.clear-dirty;
        return;
    }

    self!ensure-handle;
    self!sync-from-store if @!store-path.elems > 0;
    # ncuplot draws to its sub-plane on every notcurses_render; we
    # don't have any explicit cell-writes to do here.
    self.clear-dirty;
}

method !render-empty() {
    return if $!empty-message eq '' || self.rows == 0 || self.cols == 0;
    self.apply-style(self.theme.text-dim);
    my $msg = $!empty-message.substr(0, self.cols);
    my $row = self.rows div 2;
    my $col = max(0, (self.cols - $msg.chars) div 2);
    ncplane_putstr_yx(self.plane, $row, $col, $msg);
}

method !sync-from-store() {
    return unless self.store && $!plot.defined;
    my $samples = self.store.get-in(|@!store-path);
    return without $samples.defined;
    my @list = $samples.list;

    # Push samples we haven't seen yet.
    for ($!last-pushed-idx + 1) ..^ @list.elems -> $i {
        my $entry = @list[$i];
        # Accept (x, y) as a 2-element list/Pair OR a hash with x/y keys.
        my ($x, $y);
        given $entry {
            when Pair        { $x = $i;        $y = $entry.value }
            when Positional  { $x = $entry[0]; $y = $entry[1] }
            when Associative { $x = $entry<x> // $i; $y = $entry<y> }
            default          { $x = $i;        $y = $entry }
        }
        self!push-to-handle($x.Int, $y.Real);
    }
    $!last-pushed-idx = @list.elems - 1;
}

method !on-resize() {
    self!destroy-handle;
    # Handle will be recreated on next render at the new dims.
}

method park() {
    self!destroy-handle;
    callsame;
}

method destroy() {
    self!destroy-handle;
    self!destroy-plane;
}

#| Returns True iff the native plot handle is currently allocated.
#| Mostly useful in tests verifying lifecycle behavior.
method has-handle(--> Bool) {
    $!plot.defined;
}
