=begin pod

=head1 NAME

Selkie::Widget::Sparkline - Inline single-row chart using Unicode block glyphs

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Sparkline;
use Selkie::Sizing;

# Static data — fixed series
my $sl = Selkie::Widget::Sparkline.new(
    data   => [1, 4, 2, 8, 5, 9, 3, 7],
    sizing => Sizing.fixed(1),
);

# Streaming — push samples as they arrive
my $stream = Selkie::Widget::Sparkline.new(sizing => Sizing.fixed(1));
$cpu-supply.tap: -> $sample { $stream.push-sample($sample) };

# Reactive — read from a store path that holds the array
my $bound = Selkie::Widget::Sparkline.new(
    store-path => <metrics latency-history>,
    sizing     => Sizing.fixed(1),
);

=end code

=head1 DESCRIPTION

A single-row inline chart that maps numeric values to the Unicode
"lower one-eighth block" series:

  ▁ ▂ ▃ ▄ ▅ ▆ ▇ █

Each cell shows one sample. The widget's width determines how many
samples are visible — when the buffer overflows, the oldest sample
is discarded (FIFO ring buffer).

Sparklines are designed to live inline with text or in table cells,
not as standalone visualisations. For a full-fledged line chart with
axes and legends, use L<Selkie::Widget::LineChart> (static data) or
L<Selkie::Widget::Plot> (streaming).

=head2 Construction modes

=item B<Static> — pass C<:data(@arr)> for a fixed sample series. The widget renders the same data every frame.
=item B<Streaming> — construct without C<:data>, then call C<.push-sample($v)> as new samples arrive. Internal ring buffer caps at the widget's column count.
=item B<Reactive> — pass C<:store-path<a b c>> to read the sample array from a store path on each render. Subscription marks the widget dirty when the value changes.

The three modes are mutually exclusive: pass exactly one of C<:data>
or C<:store-path>, or neither (streaming). Mixing throws at TWEAK.

=head2 Value mapping

Values are mapped linearly from C<[min, max]> (auto-derived from the
buffer) onto the eight glyph levels. By default C<min> is the
minimum sample seen and C<max> the maximum; pass explicit C<:min> /
C<:max> to fix the range across renders (useful when streaming so
the heights don't jitter as new samples shift the auto-range).

C<NaN> samples render as a space (the cell is skipped). Negative or
positive infinities clamp to the corresponding edge glyph.

=head1 EXAMPLES

=head2 Inline in a status bar

=begin code :lang<raku>

use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::Sparkline;
use Selkie::Sizing;

my $status = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$status.add: Selkie::Widget::Text.new(text => 'CPU: ', sizing => Sizing.fixed(5));
$status.add: $cpu-sparkline,                         sizing => Sizing.fixed(20);
$status.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

=end code

=head2 In a Table cell

Embed sparklines in a table column to show per-row history. The
hand-rolled implementation has no native handle, so it's cheap to
instantiate one per row:

=begin code :lang<raku>

use Selkie::Widget::Table;

my $table = Selkie::Widget::Table.new(...);
$table.add-column(
    name     => 'history',
    width    => 20,
    renderer => -> %row {
        Selkie::Widget::Sparkline.new(
            data   => %row<latency-samples>,
            sizing => Sizing.fixed(1),
        );
    },
);

=end code

=head2 Streaming with a fixed range

Auto-range jitter is annoying when you want to see absolute trends.
Pin the range to your domain knowledge:

=begin code :lang<raku>

my $cpu-spark = Selkie::Widget::Sparkline.new(
    min    => 0,           # CPU is 0..100%
    max    => 100,
    sizing => Sizing.fixed(1),
);
$cpu-supply.tap: -> $sample { $cpu-spark.push-sample($sample) };

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::LineChart> — full chart with axes, legends, multi-series
=item L<Selkie::Widget::Plot> — streaming chart with native ncuplot ring buffer
=item L<Selkie::Plot::Scaler> — the value→cell mapping primitive

=end pod

use Notcurses::Native;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Plot::Scaler;

unit class Selkie::Widget::Sparkline does Selkie::Widget;

# The eight block-glyph levels, lowest to highest. A NaN sample maps
# to ' ' (rendered as a blank cell).
constant @LEVELS = ' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█';

#| Static sample list. Mutually exclusive with C<store-path>.
has Real @.data;

#| Reactive store path — list-of-strings forming the lookup. Mutually
#| exclusive with C<data>.
has Str @.store-path;

#| Optional fixed range lower bound. When unset, the minimum across
#| the current buffer is used (auto-range).
has Real $.min;

#| Optional fixed range upper bound. See C<min>.
has Real $.max;

#| Message rendered when there are no samples yet. This is the
#| expected startup state for monitoring dashboards, so defaults to
#| a calm placeholder rather than nothing. Disable by setting to the
#| empty string.
has Str $.empty-message = 'No data';

# Internal ring buffer for streaming mode. Sized lazily to match
# widget cols on first push.
has Real @!ring;

submethod TWEAK {
    die "Selkie::Widget::Sparkline: pass at most one of :data or :store-path"
        if @!data.elems > 0 && @!store-path.elems > 0;

    if @!data.elems > 0 {
        @!ring = @!data;
    }
}

method on-store-attached($store) {
    return unless @!store-path.elems > 0;
    self.once-subscribe(
        'sparkline-' ~ self.widget-id,
        |@!store-path,
    );
}

#|( Append a single sample to the streaming ring buffer. When the
    buffer reaches the widget's column count, the oldest sample is
    discarded. No-op in C<:data> or C<:store-path> mode (the buffer
    is owned by the data source, not the widget). )
method push-sample(Real $v) {
    return if @!data.elems > 0 || @!store-path.elems > 0;
    @!ring.push: $v;
    # Cap to current width. cols may be 0 before plane attach — use
    # a generous fallback so we don't lose samples then.
    my $cap = self.cols > 0 ?? self.cols !! 1024;
    @!ring.shift while @!ring.elems > $cap;
    self.mark-dirty;
}

#|( Replace the static data array. Only valid in C<:data> mode. )
method set-data(@new) {
    die "Selkie::Widget::Sparkline.set-data: only valid in :data mode"
        if @!store-path.elems > 0;
    @!data = @new.list;
    @!ring = @new.list;
    self.mark-dirty;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my @samples = self!current-samples;
    if @samples.elems == 0 {
        self!render-empty;
        return self.clear-dirty;
    }

    self.apply-style(self.theme.graph-line);

    my ($lo, $hi) = self!effective-range(@samples);
    my $scaler = self!scaler-for($lo, $hi);

    # Take the rightmost-N samples (N = cols) so streaming sparklines
    # show the most recent. For static :data, this is the whole array
    # if it fits, or the rightmost cols if it overflows.
    my $width = self.cols;
    my $start = max(@samples.elems - $width, 0);
    my @visible = @samples[$start ..^ @samples.elems];

    my $line = '';
    for @visible -> $v {
        $line ~= self!glyph-for($v, $scaler);
    }
    ncplane_putstr_yx(self.plane, 0, 0, $line);

    self.clear-dirty;
}

method !current-samples(--> List) {
    if @!store-path.elems > 0 && self.store {
        my $val = self.store.get-in(|@!store-path);
        return ($val.defined ?? $val.list !! ()).list;
    }
    @!ring.list;
}

method !effective-range(@samples --> List) {
    my $lo = $!min // (@samples.grep(*.defined).grep({ $_ !=== NaN }).min // 0);
    my $hi = $!max // (@samples.grep(*.defined).grep({ $_ !=== NaN }).max // 1);
    # Avoid degenerate range (all samples identical) — pad to a small
    # span so the renderer picks a stable mid-level glyph rather than
    # crashing in the scaler.
    if $lo == $hi {
        $lo -= 0.5;
        $hi += 0.5;
    }
    ($lo, $hi);
}

method !scaler-for(Real $lo, Real $hi --> Selkie::Plot::Scaler) {
    # 9 levels: index 0 = ' ' for NaN, indices 1..8 = ▁..█. Map
    # cleanly onto 8 cells.
    Selkie::Plot::Scaler.linear(min => $lo, max => $hi, cells => 8);
}

method !glyph-for(Real $v, Selkie::Plot::Scaler $scaler --> Str) {
    return @LEVELS[0] if $v === NaN;
    my $idx = $scaler.value-to-cell($v);
    # value-to-cell yields 0..7 (cells - 1); shift to 1..8 so 0
    # remains the NaN placeholder.
    return @LEVELS[0] without $idx.defined;
    @LEVELS[$idx + 1];
}

method !render-empty() {
    return if $!empty-message eq '' || self.rows == 0 || self.cols == 0;
    self.apply-style(self.theme.text-dim);
    my $msg = $!empty-message.substr(0, self.cols);
    ncplane_putstr_yx(self.plane, 0, 0, $msg);
}
