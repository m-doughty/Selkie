=begin pod

=head1 NAME

Selkie::Widget::ViewportedCardList - Row-scrolled selectable list of card widgets

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::ViewportedCardList;
use Selkie::Sizing;

# Standard chat-history pane: latest message anchored to the bottom
# of the viewport with empty space above when content is shorter
# than the pane, and auto-scroll-to-bottom while a streaming
# message grows.
my $chat = Selkie::Widget::ViewportedCardList.new(
    sizing        => Sizing.flex,
    bottom-anchor => True,
    follow-bottom => True,
);

$chat.add-item(
    $message,
    root   => $message.root,
    height => $message-height,
    border => $message.border,
);

# Streaming token arrived — last card grew. The viewport tracks the
# new bottom automatically as long as the user hasn't scrolled
# upward; if they have, the new content piles up below their parked
# position until they scroll back to the bottom.
$chat.set-item-height($chat.count - 1, $new-height);

=end code

=head1 DESCRIPTION

Like L<Selkie::Widget::CardList>, each item is an arbitrary widget with
a logical height and optional focus border. Unlike CardList, scrolling is
by content row: a viewport can start in the middle of any card.

C<bottom-anchor> aligns the last item to the bottom of the viewport
when total content is shorter than the pane (chat-history semantics
— short transcripts hug the input row, long ones scroll). C<follow-
bottom> keeps the bottom row visible as content grows or new cards
are added (streaming text, log tails). The follow latch is
maintained exclusively by user-driven scroll calls; mid-frame
content-shape changes (C<set-item-height> from a streaming token,
C<add-item> for a new message) clamp without disturbing it, so a
growing or appended message stays visible without yanking the
viewport away from a user who has scrolled up to read history.

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Cell;

use Selkie::Widget;
use Selkie::Widget::FocusableByDefault;
use Selkie::Widget::Border;
use Selkie::Event;
use Selkie::Sizing;

unit class Selkie::Widget::ViewportedCardList does Selkie::Widget does Selkie::Widget::FocusableByDefault;

#|( Module-level latch tracking whether C<libnotcurses_native_shim>'s
    C<notcurses_native_copy_cells> is callable in this process.
    Optimistic at start; flipped to False the first time the shim
    binding throws (typically "Cannot locate native library" on
    installs where the shim wasn't compiled — see Notcurses::Native's
    Build.rakumod for when that can happen). Once flipped, every
    instance uses the Raku per-cell fallback for the rest of the
    process — re-trying would just re-throw and be slower than the
    fallback. )
my Bool $shim-available = True;

#|( Test/benchmark hook to inspect or override the shim latch.
    Pass no argument to read; pass True/False to force the path
    used by subsequent C<!copy-cells> calls. Used by xt/ tests to
    drive both code paths against the same widget tree without
    needing two separate processes. NOT part of the public API —
    don't depend on this from app code; the binding's own load-
    failure detection is the right hook for runtime decisions. )
sub viewported-cardlist-shim-available(Bool $val?) is export {
    $shim-available = $val if $val.defined;
    $shim-available;
}

has @!items;
has Int $!selected = 0;
has UInt $!scroll-offset = 0;
has UInt $!content-height = 0;
has Supplier $!select-supplier = Supplier.new;
has NcplaneHandle $!backing-plane;

has Bool $.show-scrollbar = True;

#|( Anchor the last item to the bottom of the viewport when total
    content is shorter than the pane. Empty space appears above the
    cards instead of below — standard chat-history layout where the
    transcript reads upward from the input. With C<bottom-anchor =>
    False> (default) short content top-aligns. )
has Bool $.bottom-anchor = False;

#|( Auto-pin the bottom of content as it grows. When True, each
    render checks the C<follow-active> latch; if set, the new
    scroll offset snaps to C<max-offset> so streaming additions and
    height growth on the last card stay visible. The latch is
    maintained exclusively by C<scroll-to> (the funnel for every
    user-driven scroll mutator), so content-shape changes between
    frames don't disturb follow status. Any user scroll up
    disengages until they scroll back to the bottom. )
has Bool $.follow-bottom = False;

#|( Persistent tail-follow latch, only meaningful when
    C<follow-bottom> is True. Computed on every C<scroll-to> call
    based on whether the user landed at C<max-offset>. C<render>
    reads this flag without touching it; mid-frame content-shape
    changes (C<set-item-height> while a streamed message grows,
    C<add-item> appending a new card) do not affect follow status.

    The previous implementation re-derived follow per frame from
    C<scroll-offset >= max-offset> against the freshly-grown
    max-offset. That snapshot proved fragile: the very first
    streamed token grew C<content-height> past the cached
    C<scroll-offset>, the per-frame check flipped to False, and
    C<follow-bottom> silently disengaged on token #1. Tracking
    persistent state survives. )
has Bool $!follow-active = True;

#|( Layout-vs-content dirty distinction. Layout-dirty means card
    positions in C<self.plane> have shifted: scroll moved, a card's
    height changed, items were added or removed, the viewport
    resized. The whole visible region needs a full erase + full
    re-merge. Content-only dirty (this flag is False, but VCL's
    own C<is-dirty> latch is True via the parent-chain cascade
    from a descendant's C<mark-dirty>) means a card's contents
    changed at stable cell positions — typically an
    C<image-gen/progress> bar update or a streaming text token
    that fits within the existing wrapped row count. Only that
    card's region needs erasing and re-merging; other visible
    cards' cells in C<self.plane> are still valid from the
    previous frame.

    Default True so the first render does the full path. Cleared
    at the end of every render. Set by C<scroll-to> (when offset
    changes), C<set-item-height> (when height changes), C<add-
    item>, C<clear-items>, C<handle-resize>. )
has Bool $!layout-dirty = True;

submethod TWEAK() {
    self.on-click: -> $ev {
        my $row = self.local-row($ev);
        if $row >= 0 {
            my Int $content-row = $row - self!bottom-shift.Int;
            my $idx = $content-row >= 0
                ?? self!card-index-at-content-row(($!scroll-offset + $content-row.UInt).UInt)
                !! -1;
            self.select-index($idx) if $idx >= 0 && $idx != $!selected;
        }
    };

    # Mouse-wheel scrolling. Registered as an explicit on-scroll
    # handler rather than a `given/when` branch on $ev.id inside
    # handle-event: a click anywhere inside a card bubbles up through
    # Text → VBox → Border → ViewportedCardList, and the explicit
    # registration lets the framework's `dispatch-mouse-handlers` see
    # this widget as the scroll target during that bubble. Three rows
    # per tick matches CardList's "wheel = move by one logical unit"
    # idiom while staying fine-grained enough that quick wheel flicks
    # don't overshoot the next card in a row-scrolling viewport.
    self.on-scroll: -> $ev {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self.scroll-by(-3) }
            when NCKEY_SCROLL_DOWN { self.scroll-by( 3) }
        }
    };
}

method on-select(--> Supply) { $!select-supplier.Supply }
method selected(--> Int) { $!selected }
method count(--> Int) { @!items.elems }
method scroll-offset(--> UInt) { $!scroll-offset }
method content-height(--> UInt) { $!content-height }
method viewport-height(--> UInt) { self.rows }
method at-end(--> Bool) { $!scroll-offset >= self!max-offset }

#|( Read-only view of the persistent tail-follow latch. True when
    C<follow-bottom> is enabled and the user is at (or has been
    clamped to) C<max-offset>. Always True when C<follow-bottom> is
    False — the flag is simply unused. Useful for surfacing a
    "follow-mode" indicator in the UI and for tests that want to
    verify follow transitions without driving a full render. )
method follow-active(--> Bool) { $!follow-active }

method selected-item() {
    return Nil unless $!selected >= 0 && $!selected < @!items.elems;
    @!items[$!selected]<widget>;
}

method children(--> List) {
    gather {
        for @!items -> %item {
            take %item<border> if %item<border>.defined;
            take %item<root>   if %item<root>.defined;
        }
    }.List;
}

method add-item($widget, :$root!, :$height!, :$border, UInt :$min-display-height = 1) {
    $border.focus-from-store = False if $border;
    $root.parent   = self if $root.defined   && !$root.parent.defined;
    $border.parent = self if $border.defined && !$border.parent.defined;
    $root.set-store(self.store) if self.store && $root.can('set-store');
    @!items.push({ :$widget, :$root, :$height, :$border, :$min-display-height });
    self!update-content-height;
    $!layout-dirty = True;       # new card → backing-plane grows + new region
    self.mark-dirty;
}

method clear-items() {
    for @!items -> %item {
        %item<root>.destroy if %item<root>.plane;
    }
    @!items = ();
    $!selected = 0;
    $!scroll-offset = 0;
    $!content-height = 0;
    $!layout-dirty = True;       # everything is gone; force full redraw
    self.mark-dirty;
}

#|( Update the cached row height of the card at C<$idx> and clamp
    the current scroll offset to the new C<max-offset>. Does NOT
    route through C<scroll-to>: that's the user-input funnel that
    recomputes C<$!follow-active> from where the caller landed,
    and a content-shape change is not a user action. Routing
    through it would clobber the latch the moment the last card
    grew (old offset is no longer >= new max), defeating
    C<follow-bottom> on the very first streamed token. The render
    pass re-engages the latch separately if a content shrink
    leaves the offset exactly at the new max — see C<render>.

    Skips entirely (no clamp, no mark-dirty, no layout-dirty) when
    the new height equals the cached one. Streaming consumers call
    this on every token via C<self!card-height($content, $role)>;
    most tokens append to an existing wrapped line and don't grow
    the card's row count, so the call is a true no-op. Forcing a
    re-render in that case used to trigger a full ViewportedCardList
    re-merge per token. )
method set-item-height(Int $idx, Int $height) {
    return unless $idx >= 0 && $idx < @!items.elems;
    return if @!items[$idx]<height> == $height;
    @!items[$idx]<height> = $height;
    self!update-content-height;
    my UInt $max = self!max-offset;
    $!scroll-offset = $!scroll-offset min $max;
    $!layout-dirty = True;       # card positions below this one shift
    self.mark-dirty;
}

method select-index(Int $idx) {
    return unless @!items;
    my $new = ($idx max 0) min @!items.end;
    return if $new == $!selected;
    $!selected = $new;
    self!ensure-selected-visible;
    self.mark-dirty;
    $!select-supplier.emit($!selected);
}

method select-first() {
    return unless @!items;
    $!selected = 0;
    self.scroll-to-start;
}

method select-last() {
    return unless @!items;
    $!selected = @!items.end;
    self.scroll-to-end;
}

method scroll-up()   { self!select-prev }
method scroll-down() { self!select-next }

#|( Set the scroll offset to C<$row> (clamped to C<max-offset>). All
    user-driven scroll mutators — C<scroll-by>, C<scroll-page-by>,
    C<scroll-to-start>, C<scroll-to-end>, the mouse-wheel handler,
    key navigation, and C<!ensure-selected-visible> — funnel
    through here so the C<follow-active> latch updates in exactly
    one place: re-engaged at C<max-offset>, disengaged anywhere
    short of it. Content-shape changes (C<set-item-height>,
    C<add-item>) intentionally do not route through here; they
    clamp directly without disturbing the latch. )
method scroll-to(UInt $row) {
    self!update-content-height;
    my UInt $max = self!max-offset;
    my UInt $new = $row min $max;
    $!follow-active = $new >= $max;
    return if $new == $!scroll-offset;
    $!scroll-offset = $new;
    $!layout-dirty = True;       # card positions in self.plane shift
    self.mark-dirty;
}

method scroll-by(Int $delta) {
    my Int $new = $!scroll-offset + $delta;
    $new = $new max 0;
    self.scroll-to($new.UInt);
    self!select-nearest-visible-if-needed;
}

method scroll-page-by(Int $direction) {
    self.scroll-by($direction * self.rows.Int);
}

method scroll-to-start() { self.scroll-to(0) }
method scroll-to-end() { self.scroll-to(self!max-offset) }

method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    $!layout-dirty = True;       # viewport resized; full re-layout
    self!on-resize;
}

method park() {
    self.reposition(self.park-y, 0) if self.plane;
    self!park-children(@!items.map(*.<root>));
}

method destroy() {
    .<root>.destroy for @!items;
    @!items = ();
    ncplane_destroy($!backing-plane) if $!backing-plane;
    $!backing-plane = NcplaneHandle;
    self!destroy-plane;
}

#|( Two-phase render. Phase 1 walks visible items, positions and
    sizes their planes inside the backing plane, and renders each
    card whose subtree changed since the previous frame (or every
    card if C<$!layout-dirty> — scroll, height, add/remove). Phase
    2 merges the rendered card planes onto C<self.plane>:

    =item *  Layout-dirty path: erase C<self.plane> once and
       re-merge every visible card. Card positions in C<self.plane>
       have shifted, so cells from the previous frame are stale
       everywhere.

    =item *  Content-dirty-only path: leave C<self.plane> alone
       except for the dirty cards' regions. Erase each dirty
       card's slice via C<ncplane_erase_region>, then merge that
       card. Other cards' cells are still in the right place from
       last frame and survive untouched. This is the hot path
       during ComfyUI image-gen progress and during streaming
       text tokens that don't grow the wrap row count.

    The merge primitive itself is C<!copy-cells> — see that
    method's notes on why the obvious-looking C<ncplane_mergedown>
    swap is wrong here (mergedown composites at absolute pile
    coordinates, not at the scroll-translated dst we need). The
    layout/content split above is what saves work in the common
    streaming + progress cases. )
method render() {
    return without self.plane;
    self!update-content-height;

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    my UInt $content-w = self!content-width;

    if !@!items || $vh == 0 || $vw == 0 || $content-w == 0 {
        ncplane_erase(self.plane);
        $!layout-dirty = False;
        return self.clear-dirty;
    }

    my UInt $max = self!max-offset;
    if $!follow-bottom && $!follow-active {
        if $!scroll-offset != $max {
            $!scroll-offset = $max;
            $!layout-dirty = True;
        }
    } else {
        my $clamped = $!scroll-offset min $max;
        if $clamped != $!scroll-offset {
            $!scroll-offset = $clamped;
            $!layout-dirty = True;
        }
        $!follow-active = True if $!scroll-offset >= $max;
    }

    self!ensure-backing-plane($!content-height max 1, $content-w);
    # Backing plane content is always re-painted by visible cards'
    # renders; erase only when layout shifted so old card content
    # at moved positions doesn't bleed into new layout.
    ncplane_erase($!backing-plane) if $!layout-dirty;

    my Bool $show-bar = $!show-scrollbar && $!content-height > $vh;
    my @visible;
    my UInt $cum-y = 0;
    for ^@!items.elems -> $i {
        my %item = @!items[$i];
        my UInt $h = %item<height>.UInt;
        my UInt $end = $cum-y + $h;
        my Bool $visible = $end > $!scroll-offset && $cum-y < $!scroll-offset + $vh;

        if !$visible {
            %item<root>.park if %item<root>.plane;
            $cum-y = $end;
            next;
        }

        my $border = %item<border>;
        if $border {
            $border.set-has-focus($i == $!selected);
            $border.hide-top-border = False;
            $border.hide-bottom-border = False;
        }

        my $widget = %item<widget>;
        if $widget.can('set-clipped') {
            $widget.set-clipped(
                top    => $cum-y < $!scroll-offset,
                bottom => $end > $!scroll-offset + $vh,
            );
        }

        my $root = %item<root>;
        # Capture the dirty-cascade signal BEFORE the per-card
        # set-up that resizes and may flip the latch via mark-dirty.
        my Bool $card-was-dirty = !$root.plane.defined || $root.is-dirty;

        if $root.plane {
            $root.reposition($cum-y, 0);
            $root.resize($h, $content-w);
        } else {
            $root.init-plane($!backing-plane, y => $cum-y, x => 0, rows => $h, cols => $content-w);
        }
        $root.set-viewport(
            abs-y => self.abs-y + $cum-y.Int - $!scroll-offset.Int,
            abs-x => self.abs-x,
            rows  => $h,
            cols  => $content-w,
        );

        if $!layout-dirty || $card-was-dirty {
            $root.mark-dirty;
            $root.render;
        }

        # Compute the destination slice in self.plane for the
        # content-only re-merge path. Mirrors the math in
        # !merge-widget-plane but at the card-root level. Note:
        # `max 0` here is the infix clamp; `.max(0)` is the
        # sort-key method form and would type-error on 0 as a
        # Callable (see memory raku_max_min_method_trap).
        my Int $dst-y = (($cum-y.Int - $!scroll-offset.Int) max 0)
                        + self!bottom-shift.Int;
        my Int $src-clip-top = ($!scroll-offset.Int - $cum-y.Int) max 0;
        my Int $vh-clip = ($h.Int - $src-clip-top) min ($vh.Int - $dst-y);
        my UInt $card-vh = ($vh-clip max 0).UInt;

        @visible.push: %(
            :$root, :$dst-y, :$card-vh,
            should-merge => ($!layout-dirty || $card-was-dirty),
        );
        $cum-y = $end;
    }

    if $!layout-dirty {
        ncplane_erase(self.plane);
        for @visible -> %v {
            self!merge-subtree(%v<root>);
        }
    } else {
        for @visible -> %v {
            next unless %v<should-merge>;
            # Erase just this card's slice in self.plane so cells
            # in positions where the new render produces empty
            # source cells (mergedown skips those) don't keep
            # showing the previous frame's content. Width is
            # $content-w, not $vw — the rightmost column belongs to
            # the scrollbar and gets re-painted by !render-scrollbar.
            ncplane_erase_region(self.plane, %v<dst-y>, 0,
                                 %v<card-vh>.Int, $content-w.Int)
                if %v<card-vh> > 0;
            self!merge-subtree(%v<root>);
        }
    }

    ncplane_move_yx($!backing-plane, self.park-y, 0);
    self!render-scrollbar if $show-bar;
    $!layout-dirty = False;
    self.clear-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    return True if self!check-keybinds($ev);
    return False unless @!items;

    if $ev.event-type ~~ MouseEvent {
        # Scroll wheel handled here in addition to the on-scroll TWEAK
        # registration. The explicit given/when works for the historic
        # path where this widget is the direct event target; the
        # on-scroll registration kicks in when the framework's bubble
        # finds it through `dispatch-mouse-handlers`. Belt-and-suspenders
        # — at least one of the two reliably fires regardless of how
        # the host App routes mouse events.
        given $ev.id {
            when NCKEY_SCROLL_UP   { self.scroll-by(-3); return True }
            when NCKEY_SCROLL_DOWN { self.scroll-by( 3); return True }
        }
        return True if self!dispatch-mouse-handlers($ev);
    }

    if $ev.event-type ~~ KeyEvent {
        given $ev.id {
            when NCKEY_UP {
                if $ev.has-modifier(Mod-Shift) { self.scroll-by(-1) } else { self!select-prev }
                return True;
            }
            when NCKEY_DOWN {
                if $ev.has-modifier(Mod-Shift) { self.scroll-by( 1) } else { self!select-next }
                return True;
            }
            when NCKEY_PGUP   { self.scroll-page-by(-1); return True }
            when NCKEY_PGDOWN { self.scroll-page-by( 1); return True }
            when NCKEY_HOME   { self.select-first;      return True }
            when NCKEY_END    { self.select-last;       return True }
        }
    }
    False;
}

method !select-next() {
    return unless @!items && $!selected < @!items.end;
    $!selected++;
    self!ensure-selected-visible;
    self.mark-dirty;
    $!select-supplier.emit($!selected);
}

method !select-prev() {
    return unless @!items && $!selected > 0;
    $!selected--;
    self!ensure-selected-visible;
    self.mark-dirty;
    $!select-supplier.emit($!selected);
}

method !update-content-height() {
    $!content-height = 0;
    $!content-height += .<height>.UInt for @!items;
}

method !max-offset(--> UInt) {
    my UInt $vh = self.rows;
    $!content-height > $vh ?? $!content-height - $vh !! 0;
}

method !content-width(--> UInt) {
    $!show-scrollbar ?? (self.cols - 1) max 0 !! self.cols;
}

method !ensure-backing-plane(UInt $rows, UInt $cols) {
    if $!backing-plane {
        ncplane_resize_simple($!backing-plane, $rows, $cols);
        ncplane_move_yx($!backing-plane, 0, 0);
        ncplane_move_family_below($!backing-plane, self.plane);
    } else {
        my $opts = NcplaneOptions.new(y => 0, x => 0, :$rows, :$cols);
        $!backing-plane = ncplane_create(self.plane, $opts);
        die "Failed to create ViewportedCardList backing plane" without $!backing-plane;
        ncplane_move_family_below($!backing-plane, self.plane);
    }
}

method !ensure-selected-visible() {
    return unless @!items;
    my ($top, $bot) = self!item-bounds($!selected);
    my UInt $vh = self.rows;
    if $top < $!scroll-offset {
        self.scroll-to($top);
    } elsif $bot > $!scroll-offset + $vh {
        my Int $new = $bot.Int - $vh.Int;
        self.scroll-to(($new max 0).UInt);
    }
}

method !select-nearest-visible-if-needed() {
    return unless @!items;
    my ($top, $bot) = self!item-bounds($!selected);
    return if $bot > $!scroll-offset && $top < $!scroll-offset + self.rows;
    my $idx = self!card-index-at-content-row($!scroll-offset);
    if $idx >= 0 && $idx != $!selected {
        $!selected = $idx;
        $!select-supplier.emit($!selected);
    }
}

method !item-bounds(Int $idx --> List) {
    my UInt $top = 0;
    for ^$idx -> $i { $top += @!items[$i]<height>.UInt }
    ($top, $top + @!items[$idx]<height>.UInt);
}

method !card-index-at-content-row(UInt $row --> Int) {
    my UInt $cum = 0;
    for ^@!items.elems -> $i {
        my UInt $end = $cum + @!items[$i]<height>.UInt;
        return $i if $row < $end;
        $cum = $end;
    }
    @!items.elems ?? @!items.end !! -1;
}

method !merge-subtree($widget) {
    self!merge-widget-plane($widget);
    if $widget.can('children') {
        for $widget.children -> $child {
            self!merge-subtree($child);
        }
    }
    # Border (and any single-content Container that doesn't push its
    # content into @!children) exposes its wrapped widget only via
    # .content. Without this branch the contents of a Border never get
    # merged onto self.plane and the card renders as an empty frame.
    if $widget.can('content') {
        my $content = $widget.content;
        self!merge-subtree($content) if $content.defined;
    }
}

method !merge-widget-plane($widget) {
    return without $widget.plane;
    my Int $wy = ncplane_abs_y($widget.plane) - ncplane_abs_y($!backing-plane);
    my Int $wx = ncplane_abs_x($widget.plane) - ncplane_abs_x($!backing-plane);
    my UInt $wh = $widget.rows;
    my UInt $ww = $widget.cols;
    return if $wh == 0 || $ww == 0;

    my Int $src-top = ($!scroll-offset.Int - $wy) max 0;
    my Int $src-left = (0 - $wx) max 0;
    my Int $dst-y = (($wy - $!scroll-offset.Int) max 0) + self!bottom-shift.Int;
    my Int $dst-x = $wx max 0;
    my Int $len-y = (($wy + $wh.Int) min ($!scroll-offset.Int + self.rows.Int)) - ($wy + $src-top);
    my Int $len-x = (($wx + $ww.Int) min self!content-width.Int) - ($wx + $src-left);
    return if $len-y <= 0 || $len-x <= 0;

    my Bool $handled-image = False;
    if $widget.can('render-viewport-crop') {
        $handled-image = $widget.render-viewport-crop(
            parent-plane => self.plane,
            dest-y       => $dst-y,
            dest-x       => $dst-x,
            source-row   => $src-top,
            source-col   => $src-left,
            rows         => $len-y.UInt,
            cols         => $len-x.UInt,
        );
    }

    self!copy-cells(
        $widget.plane,
        src-y => $src-top,
        src-x => $src-left,
        dst-y => $dst-y,
        dst-x => $dst-x,
        rows  => $len-y.UInt,
        cols  => $len-x.UInt,
    ) unless $handled-image;
}

#|( One-call batched copy of a C<$rows × $cols> rectangle from
    C<$src> at (src-y, src-x) onto C<self.plane> at (dst-y, dst-x).
    Substitutes the source plane's base cell into empty cells so
    Border interiors carry the theme background through the copy
    (matches notcurses's own C<ncplane_at_yx> behaviour).

    Fast path: C<libnotcurses_native_shim>'s
    C<notcurses_native_copy_cells> — one C call per invocation
    instead of 5+ NativeCall trips per cell. For a typical 30×100
    widget plane that's a 15,000× reduction in boundary crossings.

    Fallback path (C<!copy-cells-raku>): the original per-cell
    Raku loop, used when the shim isn't loadable (no C toolchain
    AND no prebuilt-bundled shim — see Notcurses::Native's
    Build.rakumod). Functionally identical, just slower; the latch
    flips once per process so we don't retry on every render.

    Other primitives considered and rejected:

    =item C<ncplane_mergedown> — composites at absolute pile
       coordinates (validates the slice args but doesn't actually
       use them; see C<src/lib/render.c> in notcurses), not at the
       scroll-translated dst we need. Cards' planes live at
       backing-plane positions, so mergedown paints them there.
       Wrong for our usage.
    =item C<ncplane_contents> — bulk-reads cell glyphs but discards
       styles/colors. Lossy. )
method !copy-cells(
    NcplaneHandle $src,
    Int :$src-y!,
    Int :$src-x!,
    Int :$dst-y!,
    Int :$dst-x!,
    UInt :$rows!,
    UInt :$cols!,
) {
    if $shim-available {
        my $rc = try notcurses_native_copy_cells(
            $src, self.plane,
            $src-y, $src-x,
            $dst-y, $dst-x,
            $rows, $cols,
        );
        return if $rc.defined;
        # Shim binding failed — most likely the lib wasn't compiled
        # at install time and isn't in the prebuilt either. Flip the
        # latch so subsequent calls skip straight to the Raku path,
        # and report once so the user knows perf is degraded.
        $shim-available = False;
        note "⚠️  notcurses_native_copy_cells unavailable ({ $!.message // 'unknown' }); "
           ~ "Selkie::Widget::ViewportedCardList falling back to "
           ~ "per-cell Raku merge (correct, but ~5000× more "
           ~ "NativeCall trips per render). Install / reinstall "
           ~ "Notcurses::Native with a C toolchain available, or "
           ~ "wait for a prebuilt release that ships the shim, to "
           ~ "get the fast path back.";
    }
    self!copy-cells-raku(
        $src,
        :$src-y, :$src-x,
        :$dst-y, :$dst-x,
        :$rows, :$cols,
    );
}

#|( Per-cell Raku fallback for !copy-cells. Used only when the
    notcurses native shim isn't loadable. Reads each source cell
    via C<ncplane_at_yx_cell> (the heap-stable variant of
    C<ncplane_at_yx> — see C<memory/nativecall_str_free_trap.md>
    for why we don't use the malloc'ing version), substitutes the
    source plane's base cell when a cell has an empty glyph (the
    Border-interior case), and writes each cell to C<self.plane>
    via C<ncplane_putstr_yx> with matched styles + channels. )
method !copy-cells-raku(
    NcplaneHandle $src,
    Int :$src-y!,
    Int :$src-x!,
    Int :$dst-y!,
    Int :$dst-x!,
    UInt :$rows!,
    UInt :$cols!,
) {
    my $cell = Nccell.new;
    my $base = Nccell.new;
    ncplane_base($src, $base);
    my $base-egc      = nccell_extended_gcluster($src, $base);
    my $base-styles   = $base.stylemask;
    my $base-channels = $base.channels;

    for ^$rows -> $row {
        for ^$cols -> $col {
            my $bytes = ncplane_at_yx_cell(
                $src,
                $src-y + $row.Int,
                $src-x + $col.Int,
                $cell,
            );
            next if $bytes < 0;
            my $egc = nccell_extended_gcluster($src, $cell);
            my ($write-egc, $write-styles, $write-channels);
            if !$egc.defined || $egc eq '' {
                $write-egc      = $base-egc;
                $write-styles   = $base-styles;
                $write-channels = $base-channels;
            } else {
                $write-egc      = $egc;
                $write-styles   = $cell.stylemask;
                $write-channels = $cell.channels;
            }
            next unless $write-egc.defined && $write-egc.chars;
            ncplane_set_styles(self.plane, $write-styles);
            ncplane_set_channels(self.plane, $write-channels);
            ncplane_putstr_yx(
                self.plane,
                $dst-y + $row.Int,
                $dst-x + $col.Int,
                $write-egc,
            );
        }
    }
}

method !bottom-shift(--> UInt) {
    $!bottom-anchor && $!content-height < self.rows
        ?? self.rows - $!content-height
        !! 0;
}

method !render-scrollbar() {
    my UInt $vh = self.rows;
    my UInt $sx = self.cols - 1;
    my $track-style = self.theme.scrollbar-track;
    my $thumb-style = self.theme.scrollbar-thumb;
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
