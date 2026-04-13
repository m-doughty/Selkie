=begin pod

=head1 NAME

Selkie::Widget::ProgressBar - Determinate or indeterminate progress bar

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::ProgressBar;
use Selkie::Sizing;

# Determinate: value 0.0 to 1.0
my $pb = Selkie::Widget::ProgressBar.new(sizing => Sizing.fixed(1));
$pb.set-value(0.42);                 # 42%

# Indeterminate: animated bouncing block
my $spinner = Selkie::Widget::ProgressBar.new(
    indeterminate    => True,
    show-percentage  => False,
    sizing           => Sizing.fixed(1),
);
$app.on-frame: { $spinner.tick };    # advance animation each frame

=end code

=head1 DESCRIPTION

A horizontal bar showing progress. Two modes:

=item B<Determinate> — C<value> 0.0–1.0 fills the bar left to right. Shows percentage unless disabled.
=item B<Indeterminate> — a small block bounces left-right inside the bar. Animation advances by one step every C<frames-per-step> calls to C<tick>. No percentage shown.

Non-focusable by default (it's a display widget).

=head1 EXAMPLES

=head2 Job progress driven by the store

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'progress',
    -> $s {
        my $done  = $s.get-in('job', 'step')  // 0;
        my $total = $s.get-in('job', 'total') // 1;
        $total == 0 ?? 0.0 !! ($done / $total).Rat;
    },
    -> $frac { $pb.set-value($frac) },
    $pb,
);

=end code

=head2 Toggle animation based on running state

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'spinner-running',
    -> $s { $s.get-in('job', 'running') // False },
    -> Bool $running { $spinner.indeterminate = $running },
    $spinner,
);

=end code

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::ProgressBar does Selkie::Widget;

#| Current progress, 0.0 to 1.0. Ignored when C<indeterminate> is True.
has Rat $.value = 0.0;

#| Render a "NN%" suffix after the bar (determinate mode only).
has Bool $.show-percentage = True;

#| Switch to bouncing-block animation mode. Flip at runtime with
#| direct assignment (it's C<is rw>) — the bar updates on the next
#| C<tick>.
has Bool $.indeterminate is rw = False;

#| Character used for the filled portion of the bar.
has Str $.fill-char = '█';

#| Character used for the empty portion.
has Str $.empty-char = '░';

has UInt $!bounce-pos = 0;
has Int $!bounce-dir = 1;
has UInt $!bounce-width = 3;
has UInt $!frame-count = 0;

#| Indeterminate bounce speed: one step per N ticks. Default 4 gives a
#| comfortable animation at 60fps.
has UInt $.frames-per-step = 4;

method new(*%args --> Selkie::Widget::ProgressBar) {
    %args<focusable> //= False;
    callwith(|%args);
}

#| Current value, clamped 0.0..1.0.
method value(--> Rat) { $!value }

#|( Set progress to a fraction 0.0..1.0. Out-of-range inputs are
    clamped. No-op if the value is unchanged (so it's safe to call
    on every frame). )
method set-value(Rat(Cool) $v) {
    my Rat $clamped = ($v.Rat max 0.0) min 1.0;
    return if $clamped == $!value;
    $!value = $clamped;
    self.mark-dirty;
}

#|( Advance the indeterminate animation by one frame. No-op in
    determinate mode. Call from a frame callback:

        $app.on-frame: { $spinner.tick };
    )
method tick() {
    return unless $!indeterminate;
    $!frame-count++;
    return unless $!frame-count >= $!frames-per-step;
    $!frame-count = 0;

    my UInt $bar-width = self!bar-width;
    return unless $bar-width > 0;

    my UInt $effective-width = $!bounce-width min $bar-width;

    $!bounce-pos = ($!bounce-pos.Int + $!bounce-dir).UInt;
    if $!bounce-pos + $effective-width >= $bar-width {
        $!bounce-pos = $bar-width - $effective-width;
        $!bounce-dir = -1;
    } elsif $!bounce-pos <= 0 {
        $!bounce-pos = 0;
        $!bounce-dir = 1;
    }

    self.mark-dirty;
}

method !bar-width(--> UInt) {
    my UInt $w = self.cols;
    if $!show-percentage && !$!indeterminate {
        $w = ($w - 5) max 1;
    }
    $w;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $w = self.cols;
    my UInt $bar-width = self!bar-width;

    my $style = self.theme.text;
    self.apply-style($style);

    my Str $bar;
    if $!indeterminate {
        my UInt $effective-width = $!bounce-width min $bar-width;
        $bar = $!empty-char x $bar-width;
        $bar = $bar.substr(0, $!bounce-pos)
             ~ ($!fill-char x $effective-width)
             ~ $bar.substr($!bounce-pos + $effective-width);
    } else {
        my UInt $filled = ($bar-width * $!value).round.UInt min $bar-width;
        my UInt $empty = $bar-width - $filled;
        $bar = ($!fill-char x $filled) ~ ($!empty-char x $empty);
    }

    if $!show-percentage && !$!indeterminate {
        my $pct = ($!value * 100).round.Int;
        my $pct-str = sprintf('%3d%%', $pct);
        ncplane_putstr_yx(self.plane, 0, 0, $bar ~ ' ' ~ $pct-str);
    } else {
        ncplane_putstr_yx(self.plane, 0, 0, $bar);
    }

    self.clear-dirty;
}
