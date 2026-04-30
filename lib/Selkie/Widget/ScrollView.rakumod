=begin pod

=head1 NAME

Selkie::Widget::ScrollView - Virtual-scrolling container for long content

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::ScrollView;
use Selkie::Widget::Text;
use Selkie::Sizing;

my $scroll = Selkie::Widget::ScrollView.new(sizing => Sizing.flex);
my $body = Selkie::Widget::Text.new(
    text   => slurp('long-document.txt'),
    sizing => Sizing.flex,
);
$scroll.add($body);

# Pin to bottom for streaming / log views — auto-scroll to keep the
# newest content visible until the user scrolls up.
my $tail = Selkie::Widget::ScrollView.new(
    sizing        => Sizing.flex,
    follow-bottom => True,
);

=end code

=head1 DESCRIPTION

A container that renders only the rows of its children currently in
view. Children report their C<logical-height>; ScrollView uses this to
compute scrollable extent and renders the correct slice via
C<render-region>.

Arrow keys, PgUp/PgDown, Home/End, and the mouse wheel scroll when
the widget is focused. A scrollbar appears on the right edge when
content is taller than the viewport.

The scrollbar's column is reserved unconditionally when
C<show-scrollbar> is True, even when no scrollbar is currently shown
— this prevents the wrap-feedback loop where adding a scrollbar
narrows the body, the body rewraps to one extra line, the new line
overflows, and the row gets clipped under the scrollbar. The cost is
one column of right-edge real-estate when content fits; the benefit
is the slot is always sized for the worst case so content never
truncates unexpectedly.

C<follow-bottom> turns ScrollView into a tail-following pane: each
render captures whether the user was at the bottom before content
changed, and if so, snaps the new scroll offset to the new max so
the latest content stays visible. Designed for log views and
streaming-text bodies. Any scroll-up by the user disables the
follow until they scroll back to the bottom.

Children should implement C<logical-height> and, ideally,
C<render-region(offset, height)>. C<Text>, C<RichText>, and
C<TextStream> do. Plain widgets that don't will be rendered at full
height — fine for short children.

=head1 SEE ALSO

=item L<Selkie::Widget::TextStream> — scrollable log with its own ring buffer
=item L<Selkie::Widget::CardList> — interactive variable-height list

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Event;
use Selkie::Sizing;

unit class Selkie::Widget::ScrollView does Selkie::Container;

has UInt $!scroll-offset = 0;
has Bool $.show-scrollbar = True;
has UInt $!content-height = 0;

#|( Persistent tail-follow state, only meaningful when
    C<follow-bottom> is True. Computed once on every user-driven
    C<scroll-to> call (the funnel that scroll-by, scroll-page-by,
    scroll-to-end, scroll-to-start, mouse wheel, and scrollbar drag
    all route through), based on whether the user landed at
    C<max-offset> or not. C<render> reads this flag without
    touching it — content-height changes between frames don't
    affect follow status.

    The previous implementation computed "follow active" per
    render by checking C<scroll-offset >= max-offset> against the
    OLD content-height. That snapshot proved fragile: CardList
    resizes mid-frame change C<self.rows> and so C<max-offset>
    before content-height is even re-measured, and children with
    lazy C<logical-height> (RichText) can briefly report stale
    heights between C<set-content> and the next render. Either
    fragility flipped the per-frame check to False and silently
    disabled tail-follow for streaming bodies. Tracking persistent
    state survives both. )
has Bool $!follow-active = True;

submethod TWEAK() {
    # Click + drag on the scrollbar column drags the thumb. The
    # mapping is proportional: cursor row → scroll-offset such that
    # thumb-y == cursor-row (clamped to thumb-track bounds). Click
    # outside the scrollbar column falls through; click inside the
    # body would normally land on a child via deeper hit-testing.
    self.on-mouse-down: -> $ev {
        if $!show-scrollbar {
            my $col = self.local-col($ev);
            if $col == (self.cols - 1).Int {
                self!scrollbar-jump-to-row(self.local-row($ev).UInt);
            }
        }
    };
    self.on-drag: -> $ev {
        if $!show-scrollbar {
            # Drag captures keep us as the target even when the
            # cursor leaves our bounds; recompute against raw event
            # y so the thumb tracks the cursor.
            my $raw-row = $ev.y - self.abs-y;
            my $clamped = ($raw-row max 0) min (self.rows - 1).Int;
            self!scrollbar-jump-to-row($clamped.UInt);
        }
    };
}

# Map a viewport row to a scroll-offset such that the thumb lands at
# that row. Clamps to the thumb-track range so dragging past the
# extremes saturates instead of jumping erratically.
method !scrollbar-jump-to-row(UInt $row) {
    my UInt $vh = self.rows;
    return unless $vh > 0;
    my UInt $max = self!max-offset;
    return unless $max > 0;
    my Rat $thumb-ratio = $vh / ($!content-height max 1);
    my UInt $thumb-h = ($vh * $thumb-ratio).ceiling.UInt max 1;
    my UInt $track = ($vh - $thumb-h) max 1;
    my UInt $clamped = $row min $track;
    self.scroll-to(($clamped * $max / $track).floor.UInt);
}

#|( Auto-pin to the bottom of content as it grows. When True, each
    render checks whether the scroll offset was at C<max-offset> just
    before C<update-content-height> ran; if so, it snaps the new
    offset to the new C<max-offset>. Streaming additions stay
    visible without manual scrolling. When False, scroll position
    is preserved across content changes (with clamping). )
has Bool $.follow-bottom = False;

method scroll-offset(--> UInt) { $!scroll-offset }
method content-height(--> UInt) { $!content-height }
method viewport-height(--> UInt) { self.rows }

#|( Read-only view of the persistent tail-follow flag. True when
    C<follow-bottom> is enabled and the user is currently at (or
    has been clamped to) C<max-offset>. Useful for app code that
    wants to surface a "follow-mode" indicator in the UI, and for
    tests to verify follow transitions without driving a full
    render. Always True for views constructed with
    C<follow-bottom => False> — the flag is simply unused. )
method follow-active(--> Bool) { $!follow-active }

method scroll-to(UInt $row) {
    my UInt $max = self!max-offset;
    $!scroll-offset = $row min $max;
    # Re-evaluate tail-follow state from where the user landed.
    # Reaching max-offset re-engages follow; landing anywhere
    # short of it disengages until they scroll back. This is the
    # single point that maintains $!follow-active — see the
    # attribute comment for the rationale.
    $!follow-active = $!scroll-offset >= $max;
    self.mark-dirty;
}

method scroll-by(Int $delta) {
    my Int $new = $!scroll-offset + $delta;
    $new = $new max 0;
    self.scroll-to($new.UInt);
}

#|( Scroll by one viewport-height in the given C<$direction>
    (typically C<+1> for PgDown, C<-1> for PgUp). Centralises the
    "what does a page mean" decision in the ScrollView itself —
    callers don't need to query viewport-height first. )
method scroll-page-by(Int $direction) {
    self.scroll-by($direction * self.rows.Int);
}

method scroll-to-start() { self.scroll-to(0) }

method scroll-to-end() { self.scroll-to(self!max-offset) }

method at-end(--> Bool) { $!scroll-offset >= self!max-offset }

method !max-offset(--> UInt) {
    my UInt $vh = self.rows;
    $!content-height > $vh ?? $!content-height - $vh !! 0;
}

#|( Width available to children, exclusive of the reserved scrollbar
    column. Reserved unconditionally when C<show-scrollbar> is True
    so children's wrapping is stable across scrollbar visibility
    changes. See class docs for the rationale. )
method !content-width(--> UInt) {
    $!show-scrollbar ?? (self.cols - 1) max 0 !! self.cols;
}

method !measure-child($child --> UInt) {
    return $child.logical-height.UInt if $child.can('logical-height');
    return $child.sizing.value.UInt   if $child.sizing.mode ~~ SizeFixed;
    $child.rows;
}

method !update-content-height() {
    $!content-height = 0;
    for self.children -> $child {
        $!content-height += self!measure-child($child);
    }
}

method render() {
    return without self.plane;

    my UInt $viewport-h = self.rows;
    my UInt $content-w  = self!content-width;

    # Phase 1: ensure every child has a plane sized at the canonical
    # content-width BEFORE we ask for logical-height. Without this,
    # a freshly-added child has cols == 0 and logical-height wraps at
    # 1 char per line, returning a wildly inflated height — which
    # then makes the follow-bottom + clamp logic snap to a phantom
    # max-offset for one frame and the body flickers when streaming
    # starts. Resizing here is cheap (no re-blit, no re-render) and
    # idempotent when cols already match.
    for self.children -> $child {
        if !$child.plane {
            $child.init-plane(self.plane,
                y => 0, x => 0, rows => 1, cols => $content-w);
        } elsif $child.cols != $content-w {
            $child.resize($child.rows max 1, $content-w);
        }
    }

    # Phase 2: refresh content-height from children (now sized
    # correctly by Phase 1), then resolve scroll position from the
    # persistent C<$!follow-active> flag. The flag is maintained
    # by C<scroll-to> on user input and is unaffected by between-
    # frame height fragilities — see the attribute comment.
    self!update-content-height;

    my UInt $new-max = self!max-offset;
    if $!follow-bottom && $!follow-active {
        $!scroll-offset = $new-max;
    } else {
        $!scroll-offset = $!scroll-offset min $new-max;
        # If a content shrink (or viewport grow) clamped us
        # exactly to max-offset, re-engage follow. The user is
        # back at the tail even though they didn't actively scroll
        # there — typical cause is a sibling card collapsing
        # (reasoning toggle, multi-line input shrink, width
        # change wrapping fewer rows) which lowers our max-offset
        # past where the user previously parked. Without this,
        # follow stays disengaged forever after the first
        # involuntary land-at-tail.
        $!follow-active = True if $!scroll-offset >= $new-max;
    }

    ncplane_erase(self.plane);

    # Phase 3: place each child. Visible portion gets a positioned +
    # resized plane and a render-region call (or full render if the
    # child can't slice). Anything entirely outside the viewport is
    # parked far off-canvas via Widget.park — the previous
    # `reposition(viewport-h, 0)` left the plane at the BOTTOM EDGE
    # of the ScrollView, with its rows extending into whatever
    # widget lived below us in the parent layout. That painted
    # ghost content over the next sibling.
    my Bool $show-bar = $!show-scrollbar && $!content-height > $viewport-h;
    my UInt $cum-y = 0;

    for self.children -> $child {
        my UInt $child-h   = self!measure-child($child);
        my UInt $child-end = $cum-y + $child-h;

        my Bool $invisible = $child-end <= $!scroll-offset
                          || $cum-y    >= $!scroll-offset + $viewport-h;

        if $invisible {
            $child.park if $child.plane;
        } else {
            my UInt $visible-start = ($!scroll-offset max $cum-y) - $cum-y;
            my UInt $screen-y      = ($cum-y - $!scroll-offset) max 0;
            my UInt $visible-rows  = ($child-h - $visible-start) min ($viewport-h - $screen-y);

            $child.reposition($screen-y, 0);
            $child.resize($visible-rows, $content-w);

            $child.set-viewport(
                abs-y => self.abs-y + $screen-y,
                abs-x => self.abs-x,
                rows  => $visible-rows,
                cols  => $content-w,
            );

            if $child.can('render-region') {
                $child.render-region(offset => $visible-start, height => $visible-rows);
            } else {
                $child.render;
            }
        }
        $cum-y = $child-end;
    }

    self!render-scrollbar if $show-bar;
    self.clear-dirty;
}

method !render-scrollbar() {
    my UInt $vh = self.rows;
    my UInt $sx = self.cols - 1;

    my $track-style = self.theme.scrollbar-track;
    my $thumb-style = self.theme.scrollbar-thumb;

    # Thumb position and size from current scroll state. max-offset is
    # guaranteed > 0 here because the caller only calls us when content
    # exceeds the viewport.
    my Rat $thumb-ratio = $vh / $!content-height;
    my UInt $thumb-h = ($vh * $thumb-ratio).ceiling.UInt max 1;
    my UInt $thumb-y = (($!scroll-offset / self!max-offset) * ($vh - $thumb-h)).floor.UInt;

    for ^$vh -> $row {
        if $row >= $thumb-y && $row < $thumb-y + $thumb-h {
            ncplane_set_fg_rgb(self.plane, $thumb-style.fg) if $thumb-style.fg.defined;
            ncplane_set_bg_rgb(self.plane, $thumb-style.bg) if $thumb-style.bg.defined;
            ncplane_putstr_yx(self.plane, $row, $sx, '┃');
        } else {
            ncplane_set_fg_rgb(self.plane, $track-style.fg) if $track-style.fg.defined;
            ncplane_set_bg_rgb(self.plane, $track-style.bg) if $track-style.bg.defined;
            ncplane_putstr_yx(self.plane, $row, $sx, '│');
        }
    }
}

method handle-event(Selkie::Event $ev --> Bool) {
    return True if self!check-keybinds($ev);

    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self.scroll-by(-3); return True }
            when NCKEY_SCROLL_DOWN { self.scroll-by(3);  return True }
        }
        return True if self!dispatch-mouse-handlers($ev);
    }
    if $ev.event-type ~~ KeyEvent {
        given $ev.id {
            when NCKEY_UP     { self.scroll-by(-1);    return True }
            when NCKEY_DOWN   { self.scroll-by(1);     return True }
            when NCKEY_PGUP   { self.scroll-page-by(-1); return True }
            when NCKEY_PGDOWN { self.scroll-page-by(1);  return True }
            when NCKEY_HOME   { self.scroll-to-start;    return True }
            when NCKEY_END    { self.scroll-to-end;      return True }
        }
    }
    False;
}
