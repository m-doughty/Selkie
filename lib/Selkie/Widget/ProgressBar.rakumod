use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::ProgressBar does Selkie::Widget;

has Rat $.value = 0.0;
has Bool $.show-percentage = True;
has Bool $.indeterminate is rw = False;
has Str $.fill-char = '█';
has Str $.empty-char = '░';

# Indeterminate animation state
has UInt $!bounce-pos = 0;
has Int $!bounce-dir = 1;
has UInt $!bounce-width = 3;
has UInt $!frame-count = 0;
has UInt $.frames-per-step = 4;   # advance bounce every N ticks

method new(*%args --> Selkie::Widget::ProgressBar) {
    %args<focusable> //= False;
    callwith(|%args);
}

method value(--> Rat) { $!value }

method set-value(Rat(Cool) $v) {
    my Rat $clamped = ($v.Rat max 0.0) min 1.0;
    return if $clamped == $!value;
    $!value = $clamped;
    self.mark-dirty;
}

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
        # "100%" = 4 chars + 1 space
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
