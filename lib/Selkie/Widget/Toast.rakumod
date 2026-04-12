use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

# Temporary overlay message that auto-dismisses after a duration.
# Renders as a centered text bar at the bottom of the screen.
#
# Toast does NOT own a backing plane in the regular Selkie sense — owning a
# full-screen plane would obscure everything behind it. Instead Toast
# manages a small `toast-plane` directly as a child of the parent stdplane,
# created on show and destroyed on hide. The widget's own `plane` slot is
# kept undefined; render-frame guards on `is-visible` rather than dirty.

unit class Selkie::Widget::Toast does Selkie::Widget;

has Str $.message = '';
has Selkie::Style $.style;
has Num $.duration = 2e0;       # seconds
has Instant $!show-time;
has Bool $!visible = False;
has NcplaneHandle $!parent-plane;
has NcplaneHandle $!toast-plane;
has UInt $!screen-rows = 0;
has UInt $!screen-cols = 0;

# Called by App in place of init-plane. We don't adopt a full-screen plane
# of our own — we just keep a reference to the parent we'll attach our
# toast-plane to.
method attach(NcplaneHandle $parent-plane, UInt :$rows, UInt :$cols) {
    $!parent-plane = $parent-plane;
    $!screen-rows = $rows;
    $!screen-cols = $cols;
}

method resize-screen(UInt $rows, UInt $cols) {
    $!screen-rows = $rows;
    $!screen-cols = $cols;
}

method show(Str:D $message, Num :$duration = 2e0,
            Selkie::Style :$style = Selkie::Style.new(fg => 0xFFFFFF, bg => 0x4A4A8A, bold => True)) {
    $!message = $message;
    $!duration = $duration;
    $!style = $style;
    $!show-time = now;
    $!visible = True;
    self.mark-dirty;
}

method is-visible(--> Bool) { $!visible }

method tick() {
    return unless $!visible;
    if now - $!show-time >= $!duration {
        $!visible = False;
        self!destroy-toast-plane;
    }
}

method render() {
    return unless $!visible;
    return without $!parent-plane;
    return unless $!screen-cols > 4;

    my $display = " {$!message} ";
    my $toast-w = ($display.chars + 4) min $!screen-cols;
    my $toast-x = ($!screen-cols - $toast-w) div 2;
    my $toast-y = $!screen-rows - 2;
    $toast-y = 0 if $toast-y < 0;

    if $!toast-plane {
        ncplane_move_yx($!toast-plane, $toast-y, $toast-x);
        ncplane_resize_simple($!toast-plane, 1, $toast-w);
    } else {
        my $opts = NcplaneOptions.new(
            y => $toast-y, x => $toast-x,
            rows => 1, cols => $toast-w,
        );
        $!toast-plane = ncplane_create($!parent-plane, $opts);
    }
    return without $!toast-plane;

    ncplane_set_fg_rgb($!toast-plane, $!style.fg) if $!style.fg.defined;
    ncplane_set_bg_rgb($!toast-plane, $!style.bg) if $!style.bg.defined;
    ncplane_set_styles($!toast-plane, $!style.styles);
    ncplane_erase($!toast-plane);

    my $pad = ($toast-w - $display.chars) max 0;
    my $left = $pad div 2;
    ncplane_putstr_yx($!toast-plane, 0, $left, $display);

    self.clear-dirty;
}

method !destroy-toast-plane() {
    if $!toast-plane {
        ncplane_destroy($!toast-plane);
        $!toast-plane = NcplaneHandle;
    }
}

method destroy() {
    self!destroy-toast-plane;
}
