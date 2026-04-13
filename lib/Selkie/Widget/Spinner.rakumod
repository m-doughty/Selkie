=begin pod

=head1 NAME

Selkie::Widget::Spinner - Tiny animated loading indicator

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Spinner;
use Selkie::Sizing;

my $spinner = Selkie::Widget::Spinner.new(sizing => Sizing.fixed(1));

# Drive animation from the main loop's frame callback
$app.on-frame: { $spinner.tick };

=end code

=head1 DESCRIPTION

A one-cell widget that cycles through a set of spinner frames, giving a
lightweight "something is happening" signal. Use it next to a status
message during async work, or anywhere you'd reach for a small
activity indicator.

Not focusable (it's display-only). Animation is manually advanced via
C<tick> — call it from C<$app.on-frame>. Throttling is wall-clock based:
C<tick> is safe to call many times per second, and the animation
advances at most once per C<interval> seconds (default 0.1 = 10fps).
This makes the visible rate independent of how often the event loop
iterates, which matters on fast-input scenarios (e.g. mouse events
flooding the queue).

Several built-in frame sets are provided as class constants:

=item C<BRAILLE> — the default; C<⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏>. Smooth-looking in most terminals.
=item C<DOTS> — C<⣾⣽⣻⢿⡿⣟⣯⣷>. Chunkier braille variant.
=item C<LINE> — C<|/-\>. Classic ASCII.
=item C<CIRCLE> — C<◐◓◑◒>. Half-circles rotating.
=item C<ARROW> — C<←↖↑↗→↘↓↙>. Pointing arrows.

Or pass your own array of strings via C<frames>.

=head1 EXAMPLES

=head2 Side-by-side with a status message

=begin code :lang<raku>

my $row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $spinner = Selkie::Widget::Spinner.new(sizing => Sizing.fixed(2));
my $status  = Selkie::Widget::Text.new(text => 'Loading...', sizing => Sizing.flex);
$row.add($spinner);
$row.add($status);
$app.on-frame: { $spinner.tick };

=end code

=head2 Hide when idle

Spinners look confusing when they're still animating in an idle app.
Toggle visibility by swapping between the spinner and an empty Text:

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'job-running',
    -> $s { $s.get-in('job', 'running') // False },
    -> Bool $running {
        # Repoint $row's first child to spinner-or-blank
        ...
    },
    $row,
);

=end code

Simpler: just stop calling C<tick> when idle. The spinner freezes on
its last frame rather than disappearing — fine for many use cases.

=head2 Custom frame set

=begin code :lang<raku>

my $custom = Selkie::Widget::Spinner.new(
    frames   => <⣀ ⣄ ⣤ ⣦ ⣶ ⣷ ⣿>,
    interval => 0.05,     # 20fps — snappy
    sizing   => Sizing.fixed(1),
);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::ProgressBar> — determinate progress with optional indeterminate bounce
=item L<Selkie::Widget::Toast> — transient message overlay

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

unit class Selkie::Widget::Spinner does Selkie::Widget;

#| Classic braille spinner — the default frame set.
our constant BRAILLE is export = <⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏>;

#| Chunkier filled-braille set.
our constant DOTS is export = <⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷>;

#| ASCII vertical bar / slash rotation.
our constant LINE is export = <| / - \\>;

#| Rotating half-circles.
our constant CIRCLE is export = <◐ ◓ ◑ ◒>;

#| Rotating arrow octants.
our constant ARROW is export = <← ↖ ↑ ↗ → ↘ ↓ ↙>;

#| The array of strings to cycle through. Defaults to C<BRAILLE>.
has @.frames = BRAILLE;

#| Minimum wall-clock interval between frame advances, in seconds.
#| Default 0.1 = 10fps, which looks smooth without being distracting.
#| Higher values give a calmer spinner; lower values a faster one.
has Real $.interval = 0.1;

#| Optional style override for the rendered character. If undefined,
#| the theme's C<text-highlight> slot is used.
has Selkie::Style $.style;

has UInt $!frame-idx = 0;
has Instant $!last-advance;

method new(*%args --> Selkie::Widget::Spinner) {
    %args<focusable> //= False;
    callwith(|%args);
}

#|( Advance the animation if at least C<interval> seconds have passed
    since the previous advance. Call from C<$app.on-frame>. Safe to
    call many times per second — the wall-clock check throttles so
    the animation rate is independent of how often the event loop
    iterates. )
method tick() {
    return without self.plane;
    my $now = now;
    if !$!last-advance.defined || ($now - $!last-advance) >= $!interval {
        $!last-advance = $now;
        $!frame-idx = ($!frame-idx + 1) % @!frames.elems;
        self.mark-dirty;
    }
}

#| Reset to the first frame. Useful when starting a new operation to
#| give a consistent visual cue.
method reset() {
    $!frame-idx = 0;
    $!last-advance = Instant;
    self.mark-dirty;
}

#| The current frame string. Useful if you want to render the spinner
#| yourself somewhere else.
method current-frame(--> Str) {
    @!frames[$!frame-idx] // '';
}

method render() {
    return without self.plane;

    # Apply style BEFORE painting, and skip ncplane_erase — all spinner
    # frames are the same cell width, so we can just overwrite the glyph
    # in place. On GPU-accelerated terminals (Kitty, Ghostty, WezTerm)
    # the erase-then-putstr pattern can read as flicker because the
    # framebuffer diff sees a two-step change. Direct overwrite looks
    # like a single glyph update.
    my $s = $!style // self.theme.text-highlight;
    self.apply-style($s);

    my $frame = self.current-frame;
    ncplane_putstr_yx(self.plane, 0, 0, $frame) if $frame;

    self.clear-dirty;
}
