=begin pod

=head1 NAME

Selkie::EffectiveBounds - The on-screen rectangle a widget may safely paint into

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::EffectiveBounds;

# Compute via Widget.effective-bounds — apps don't usually construct
# these directly:
my $eb = $some-widget.effective-bounds;

if $eb.is-empty {
    # Widget is entirely outside the visible region — don't paint
} else {
    # The visible rectangle is at ($eb.abs-y, $eb.abs-x), sized
    # $eb.rows by $eb.cols. The widget's own plane has $eb.clip-top
    # rows chopped off the top and $eb.clip-left cols off the left.
}

=end code

=head1 DESCRIPTION

Notcurses does B<not> clip a child plane's painted content to its
parent plane's bounds. A child plane sized larger than its parent
paints past the parent's edge into siblings or grandparents. Pixel
sprixels (the protocol-agnostic name covering Sixel, Kitty graphics,
and iTerm2 inline images) are even worse — they paint at absolute
terminal pixel coordinates regardless of any plane hierarchy.

C<Selkie::EffectiveBounds> is the value class returned by
L<Selkie::Widget>'s C<effective-bounds> method, which walks the parent
chain and computes the rectangular intersection of the widget's plane
with every ancestor's plane and the terminal viewport. The result is
the on-screen rectangle into which the widget may safely paint
pixels — anything outside this rectangle would bleed past an ancestor's
visible region.

L<Selkie::Widget::Image> uses this to size its blit-plane to the
visible intersection, ensuring sprixel pixels never overflow into
territory occupied by other widgets. Custom widgets that allocate
their own blit plane (following the L<Selkie::Widget::Image> pattern)
should do the same.

=head2 The clip-top / clip-left fields

When a widget is partially clipped on its top or left edge (typical
for a CardList card scrolled past the top of the viewport, or a
horizontal scroll), the visible rectangle's top-left does not coincide
with the widget's plane's top-left. C<clip-top> and C<clip-left> tell
the renderer how many rows / columns of its own plane fall outside
the visible region at the leading edges, so a sub-plane (like an
Image's blit-plane) can be positioned to land inside the visible
intersection rather than at the widget's own (0, 0).

=head1 SEE ALSO

=item L<Selkie::Widget> — owns C<effective-bounds> and C<clip-to-ancestors>
=item L<Selkie::Widget::Image> — sizes its blit-plane to these bounds and drives the surrounding sprixel destroy / re-blit lifecycle

=end pod

unit class Selkie::EffectiveBounds;

#| Top edge of the visible intersection in absolute screen coordinates.
has Int  $.abs-y     is required;

#| Left edge of the visible intersection in absolute screen coordinates.
has Int  $.abs-x     is required;

#| Height of the visible intersection in cells. Zero when the widget is
#| entirely outside its ancestors or the terminal.
has UInt $.rows      is required;

#| Width of the visible intersection in cells. Zero when the widget is
#| entirely outside its ancestors or the terminal.
has UInt $.cols      is required;

#| Number of rows of the widget's own plane that fall above the visible
#| intersection (chopped off the top by an ancestor's edge).
has UInt $.clip-top  = 0;

#| Number of columns of the widget's own plane that fall left of the
#| visible intersection (chopped off the left by an ancestor's edge).
has UInt $.clip-left = 0;

#| True when the widget has no on-screen visible area — entirely outside
#| an ancestor or the terminal viewport. Renderers should early-return
#| on C<is-empty> rather than emit any pixels.
method is-empty(--> Bool) { $!rows == 0 || $!cols == 0 }

method gist(--> Str) {
    "EffectiveBounds(y=$!abs-y, x=$!abs-x, "
    ~ "{$!rows}x{$!cols}, clip-top=$!clip-top, clip-left=$!clip-left)"
}

#|( Compute the rectangular intersection of two cell rectangles given as
    C<(abs-y, abs-x, rows, cols)> tuples. Returns a new
    C<Selkie::EffectiveBounds> with C<clip-top> and C<clip-left>
    reflecting how much of the first rectangle was chopped off its
    leading edges. C<is-empty> when the rectangles don't overlap. )
sub intersect-rect(
    Int :$ay!, Int :$ax!, UInt :$ah!, UInt :$aw!,
    Int :$by!, Int :$bx!, UInt :$bh!, UInt :$bw!,
    UInt :$clip-top  = 0,
    UInt :$clip-left = 0,
    --> Selkie::EffectiveBounds
) is export {
    my Int $top    = $ay max $by;
    my Int $left   = $ax max $bx;
    my Int $bottom = ($ay + $ah.Int) min ($by + $bh.Int);
    my Int $right  = ($ax + $aw.Int) min ($bx + $bw.Int);
    my UInt $rows  = ($bottom - $top) max 0;
    my UInt $cols  = ($right  - $left) max 0;
    Selkie::EffectiveBounds.new(
        abs-y     => $top,
        abs-x     => $left,
        :$rows, :$cols,
        clip-top  => $clip-top  + (($top  - $ay) max 0).UInt,
        clip-left => $clip-left + (($left - $ax) max 0).UInt,
    );
}

# --- Terminal viewport provider --------------------------------------------
#
# Class-level closure set by Selkie::App at init. Selkie::Widget's
# effective-bounds calls C<terminal-viewport()> as the final
# intersection step so off-screen widgets always have empty bounds
# without each container needing to know about the terminal.
# Lives in this module rather than on Selkie::Widget directly because
# Widget is a role with required methods, so methods on the role can't
# be called via class-method syntax C<Selkie::Widget.foo()> until the
# role is punned into a class — and that fails at the required-method
# check. A plain exported sub avoids the punning issue entirely.
my &TERMINAL-VIEWPORT-PROVIDER = -> { (1_000, 1_000) };

#|( Set the terminal viewport provider — a closure returning C<(rows, cols)>
    for the active terminal. C<Selkie::App> calls this on init so
    C<Selkie::Widget.effective-bounds> can intersect every widget
    against the terminal's visible area. Tests can pass a fixed-size
    closure to simulate a small terminal; pass C<{ (1_000, 1_000) }>
    to reset to the generous default. )
sub set-terminal-viewport-provider(&p --> Nil) is export {
    &TERMINAL-VIEWPORT-PROVIDER = &p;
}

#| Current terminal viewport dimensions as C<(rows, cols)>, queried
#| through the provider closure (set by L<Selkie::App> at init).
sub terminal-viewport(--> List) is export {
    TERMINAL-VIEWPORT-PROVIDER();
}
