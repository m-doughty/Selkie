=begin pod

=head1 NAME

Selkie::Widget::Toast - Transient overlay notification

=head1 SYNOPSIS

You normally use C<$app.toast(...)> which manages the widget for you:

=begin code :lang<raku>

$app.toast('Settings saved');
$app.toast('Connection lost', duration => 5e0);

=end code

Direct construction is rarely needed.

=head1 DESCRIPTION

A centered single-line message bar that auto-dismisses. By convention
rendered near the bottom of the screen.

Unlike most widgets, Toast does B<not> own a backing plane covering its
full area — that would obscure the widgets behind it. Instead it
manages a small inline plane, created on C<show> and destroyed on hide,
attached directly to the parent stdplane via C<attach>.

The C<Selkie::App.toast> wrapper hides these details: it lazily
constructs the widget, calls C<attach>, and ensures the correct size
on each invocation.

=head1 EXAMPLES

=head2 Custom styling

=begin code :lang<raku>

# Red warning style
$app.store.subscribe-with-callback(
    'errors',
    -> $s { $s.get-in('error') // '' },
    -> $msg {
        if $msg.chars > 0 {
            $app.toast($msg);   # default blue-highlight style
        }
    },
    $some-widget,
);

=end code

=head1 SEE ALSO

=item L<Selkie::App> — C<toast(...)> wrapper is the normal entry point

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

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

#|( Toast lives at screen-top, outside the widget tree, so it doesn't
    receive the normal handle-resize cascade from containers. App
    calls this directly when the terminal resizes so the toast-plane
    sits at the correct width. )
method handle-resize(UInt $rows, UInt $cols) {
    $!screen-rows = $rows;
    $!screen-cols = $cols;
}

#| Back-compat alias. Deprecated — prefer handle-resize.
method resize-screen(UInt $rows, UInt $cols) {
    self.handle-resize($rows, $cols);
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

#|( Advance the toast's lifetime clock. Called once per frame by
    C<Selkie::App>. When the duration has elapsed, the toast flips to
    invisible and its plane is destroyed.

    Returns C<True> when visibility I<just transitioned> from visible
    to invisible this tick — the caller (C<Selkie::App>) treats that
    as a signal to force one more composite render so the toast is
    actually erased from the terminal. Returns C<False> otherwise
    (toast is still visible, or was never visible this tick). )
method tick(--> Bool) {
    return False unless $!visible;
    if now - $!show-time >= $!duration {
        $!visible = False;
        self!destroy-toast-plane;
        return True;
    }
    False;
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
