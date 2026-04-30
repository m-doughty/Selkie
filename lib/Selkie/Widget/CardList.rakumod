=begin pod

=head1 NAME

Selkie::Widget::CardList - Cursor-navigated scrollable list of variable-height widgets

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::RichText;
use Selkie::Sizing;

my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

# Each card has: an inner widget, a root (often a Border wrapping the
# inner widget), a height, and an optional border for focus highlighting.
for @messages -> %msg {
    my $rich = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $rich.set-content(%msg<spans>);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($rich);
    $cards.add-item($rich, root => $border, height => 3, :$border);
}

$cards.on-select.tap: -> UInt $idx { show-detail($cards.selected-item) };

=end code

=head1 DESCRIPTION

Like L<Selkie::Widget::ListView>, but each item is an arbitrary widget
of configurable height rather than a string. The cursor moves between
cards; the selected card always fully fits in the viewport, and the
card at the opposite end may be partially clipped (with a visual
truncation hint if the card's widget supports C<set-clipped>).

Use this when your items are structured: chat messages with avatars,
tasks with metadata, email threads, etc. Use C<ListView> if items are
just strings.

=head2 Keybindings

=item C<Up> / C<Down> / mouse wheel — move the selection between cards.
=item C<Home> / C<End> — jump to first / last card.
=item C<PageUp> / C<PageDown> — scroll I<within> the selected card.
      CardList prefers C<scroll-content-page-by(Int $direction)> on the
      card widget if it's available — passing C<+1> for PgDown and C<-1>
      for PgUp lets the card decide what one page means relative to its
      OWN viewport (chat messages have body viewports much smaller than
      the chat pane itself, and over-scrolling by the chat pane's row
      count would jump straight past most of the body). Falls back to
      C<scroll-content-by(±self.rows)> for legacy widgets. Cards
      without either method simply absorb the keypress (no
      cross-card movement on PgUp/PgDown — Up/Down is the only
      cross-card movement, by design, so a long scrollable card never
      surprises the user by jumping to a neighbour). Use it for chat
      messages, code blocks, log entries — anywhere a single card
      can outgrow its slot.

=head2 Item shape

Each item is registered with:

=item C<$widget> (positional) — the renderable widget inside the card (what the user sees)
=item C<:root> — the outermost container for the card (usually a Border wrapping the inner widget)
=item C<:height> — the card's logical height in rows
=item C<:border> — optional Border for focus-highlight integration

=head1 EXAMPLES

=head2 Chat messages

See C<examples/chat.raku> for the full version. In brief:

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'chat-cards',
    -> $s { $s.get-in('messages') // [] },
    -> @msgs {
        $cards.clear-items;
        for @msgs -> %m { $cards.add-item(|build-card(%m)) }
        $cards.select-last;
    },
    $cards,
);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::ListView> — simpler, string-only version
=item L<Selkie::Widget::ScrollView> — non-interactive virtual scroll

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Widget::Border;
use Selkie::Event;
use Selkie::Sizing;

unit class Selkie::Widget::CardList does Selkie::Widget;

has @!items;        # Array of hashes: { widget, root, height, border? }
has Int $!selected = 0;
has Int $!scroll-top = 0;
has Supplier $!select-supplier = Supplier.new;

#|( State carried across renders so we can detect any layout shift
    that would otherwise rely on Image's per-Image cache invalidation
    to be 100% reliable — which it isn't in practice. Sprixel
    cleanup goes via the terminal wire as an escape sequence; rapid
    sprite churn on scroll / resize occasionally lets the new blit
    land before the old remove has flushed, leaving ghost avatars at
    the previous positions. Detecting state changes here lets us
    park every card before the normal layout pass, which forces a
    fresh sprixel ID on every visible card and sidesteps the
    incremental-update reliability question entirely.

    C<@!last-heights> tracks per-item heights across renders so a
    streaming-token-driven height growth (~1% of tokens, when a
    rendered line wraps and the card grows by a row) is treated as
    a layout shift. Most streaming tokens don't change card height,
    so the snapshot comparison stays cheap and the park-all only
    fires on wraps.

    C<$!last-selected> catches selection-only changes that shift
    card positions without moving scroll-top — clicking a card
    that's already on screen recomputes C<$top-clip> in render
    based on the new selected-index, which can push every visible
    card's row offset up or down by a few cells. Without this in
    the trigger set, those clicks would re-render at a new
    geometry without first parking the avatar planes, and notcurses
    would emit the new sprixels alongside the old ghosts. )
has Int $!last-scroll-top = -1;
has Int $!last-selected = -1;
has UInt $!last-vh = 0;
has UInt $!last-vw = 0;
has @!last-heights;

#|( When True and the rendered cards (from C<scroll-top> through the
    last item) sum to less than the viewport height, render shifts
    every visible card down so the LAST item ends at the bottom of
    the viewport rather than leaving empty space below it. Designed
    for chat-style consumers where new content arrives at the
    bottom and the user expects the latest message to be anchored
    there even when the whole conversation fits on screen.

    Default False — classic top-aligned list rendering for inventory
    / file-browser / pickers (e.g. AvatarList) where empty space
    below the last item is the right behaviour. )
has Bool $.bottom-anchor = False;

method new(*%args) {
    %args<focusable> //= True;
    callwith(|%args);
}

submethod TWEAK() {
    # Click selects the card under the cursor. Card heights are
    # heterogeneous, so we walk visible items from the current
    # scroll-top and accumulate heights until we find the one the
    # click row falls inside.
    self.on-click: -> $ev {
        my $row = self.local-row($ev);
        if $row >= 0 {
            my $idx = self!card-index-at-row($row.UInt);
            self.select-index($idx) if $idx >= 0 && $idx != $!selected;
        }
    };
}

method !card-index-at-row(UInt $row --> Int) {
    return -1 unless @!items;
    my $y = 0;
    my $i = $!scroll-top;
    while $i < @!items.elems {
        my $h = @!items[$i]<height>;
        return $i if $row < $y + $h;
        $y += $h;
        last if $y >= self.rows;
        $i++;
    }
    -1;
}

method on-select(--> Supply) { $!select-supplier.Supply }
method selected(--> Int) { $!selected }
method count(--> Int) { @!items.elems }

#|( Resize own plane only. Cards are sized / positioned / parked in
    C<render> based on the current viewport — a single authoritative
    pass per frame. Cascading handle-resize here with each card's
    stored logical height had produced the "two-state plane" bug
    where cards briefly had logical-height planes that extended
    past CardList's new bounds, bleeding into whatever widget sits
    below. )
method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
}

#|( Park self plus every card root. CardList stores its items in
    C<@!items> rather than C<self.children>, so the standard
    Container.park doesn't reach them; we recurse explicitly here.
    Without this override, when a CardList scrolls or its host
    screen is swapped out, sprixels carried by Image widgets inside
    cards keep painting on the terminal at their last screen
    position. )
method park() {
    self.reposition(10_000, 0) if self.plane;
    for @!items -> %item {
        %item<root>.park if %item<root>.plane;
    }
}

method selected-item() {
    return Nil unless $!selected >= 0 && $!selected < @!items.elems;
    @!items[$!selected]<widget>;
}

#|( Expose each card's root (and its border, if any) as `children` so
    Container-level cascade helpers (notably `!unsubscribe-tree`) reach
    them. CardList stores its cards in `@!items` rather than the
    inherited `@!children` array, so without this override the cascade
    walks an empty list and leaks subscriptions anchored inside cards. )
method children(--> List) {
    gather {
        for @!items -> %item {
            take %item<border> if %item<border>.defined;
            take %item<root>   if %item<root>.defined;
        }
    }.List;
}

# --- Item management ---

method add-item($widget, :$root!, :$height!, :$border) {
    # Selection is a CardList concern, not a "focused descendant"
    # question: the selected card stays highlighted even when keyboard
    # focus moves out of the list. Disable the Border's store-driven
    # focus derivation so set-has-focus (called per-render below) is
    # the single source of truth.
    $border.focus-from-store = False if $border;

    # Wire the per-item widgets into the parent chain. Without this
    # link C<self.theme> on a card walks past CardList and falls back
    # to C<Selkie::Theme.default>, so the first C<init-plane> →
    # C<!sync-plane-base> on each card paints its base cell with the
    # framework's default palette instead of the active theme — the
    # card stays themed against the default background until the next
    # explicit C<set-theme> cascade overwrites C<$!theme>. Setting
    # parent here lets the theme inheritance walk find the live theme
    # at the moment the plane is first created.
    $root.parent   = self if $root.defined   && !$root.parent.defined;
    $border.parent = self if $border.defined && !$border.parent.defined;

    @!items.push({ :$widget, :$root, :$height, :$border });
    self.mark-dirty;
}

method clear-items() {
    for @!items -> %item {
        %item<root>.destroy if %item<root>.plane;
    }
    @!items = ();
    $!selected = 0;
    $!scroll-top = 0;
    self.mark-dirty;
}

method set-item-height(Int $idx, Int $height) {
    return unless $idx >= 0 && $idx < @!items.elems;
    @!items[$idx]<height> = $height;
    self.mark-dirty;
}

# --- Selection ---

method select-index(Int $idx) {
    return unless @!items;
    $!selected = ($idx max 0) min @!items.end;
    self!recalc-scroll;
    self.mark-dirty;
    $!select-supplier.emit($!selected);
}

method select-last() {
    return unless @!items;
    $!selected = @!items.end;
    self!recalc-scroll;
    self.mark-dirty;
}

method select-first() {
    return unless @!items;
    $!selected = 0;
    self!recalc-scroll;
    self.mark-dirty;
}

method scroll-up()   { self!select-prev }
method scroll-down() { self!select-next }

# --- Rendering ---

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    return self.clear-dirty unless @!items && $vh > 0;

    self!recalc-scroll;

    # Defense in depth for sprixel ghosting. When scroll-top, viewport
    # dims, item count, or any item's height changes between renders,
    # cards are about to shift and Image's incremental sprixel-update
    # path can leak ghosts (terminal wire drops the remove half of a
    # remove+emit pair under rapid churn). Park every item up front so
    # visible cards re-init from a clean plane state on the layout
    # pass below, forcing fresh sprixel IDs; off-screen cards stay
    # parked.
    #
    # Per-item-height tracking deliberately fires on streaming wraps
    # (the ~1% of tokens that grow a card by a row) but stays silent
    # on tokens that just append text within an existing row. Most
    # streaming frames hit the cheap "no shift" path; only the
    # rare-but-disruptive layout shifts get the heavy cleanup. This
    # keeps streaming visually clean without per-token churn.
    my @current-heights = @!items.map(*<height>);
    my Bool $heights-changed = False;
    if @current-heights.elems != @!last-heights.elems {
        $heights-changed = True;
    } else {
        for ^@current-heights.elems -> $i {
            if @current-heights[$i] != @!last-heights[$i] {
                $heights-changed = True;
                last;
            }
        }
    }
    if $!scroll-top != $!last-scroll-top
       || $!selected   != $!last-selected
       || $vh != $!last-vh
       || $vw != $!last-vw
       || $heights-changed {
        for @!items -> %item {
            %item<root>.park if %item<root>.plane;
        }
    }
    $!last-scroll-top = $!scroll-top;
    $!last-selected   = $!selected;
    $!last-vh = $vh;
    $!last-vw = $vw;
    @!last-heights = @current-heights;

    # Calculate top clip offset
    my $total-to-selected = 0;
    for $!scroll-top .. $!selected -> $i {
        $total-to-selected += @!items[$i]<height>;
    }
    my $top-clip = ($total-to-selected - $vh) max 0;

    # Bottom anchor: when the visible items (scroll-top through end)
    # don't fill the viewport, push them down so the last item lands
    # at the bottom edge instead of leaving empty space below. The
    # only legal scroll-top here is one where the whole tail fits;
    # if it didn't, recalc-scroll would have advanced scroll-top
    # already and total-from-scroll would equal the viewport.
    my $bottom-shift = 0;
    if $!bottom-anchor {
        my $total-from-scroll = 0;
        for $!scroll-top ..^ @!items.elems -> $i {
            $total-from-scroll += @!items[$i]<height>;
        }
        $bottom-shift = ($vh - $total-from-scroll) max 0;
    }

    # Render items
    my Int $y = $bottom-shift - $top-clip;
    my Int $first = $!scroll-top;
    my Int $last = $!scroll-top - 1;

    for $!scroll-top ..^ @!items.elems -> $i {
        my %item = @!items[$i];
        my $h = %item<height>;
        last if $y >= $vh;

        my $visible-top = $y max 0;
        my $visible-bot = ($y + $h) min $vh;
        my $display-h = $visible-bot - $visible-top;

        if $display-h <= 0 {
            $y += $h;
            next;
        }

        my $clipped-top = $y < 0;
        my $clipped-bot = ($y + $h) > $vh;

        # Set border flags if available
        my $border = %item<border>;
        if $border {
            $border.set-has-focus($i == $!selected);
            $border.hide-top-border = $clipped-top;
            $border.hide-bottom-border = $clipped-bot;
        }

        # Notify widget of clipping if it supports it
        my $widget = %item<widget>;
        if $widget.can('set-clipped') {
            $widget.set-clipped(:top($clipped-top), :bottom($clipped-bot));
        }

        my $root = %item<root>;
        if $root.plane {
            $root.reposition($visible-top, 0);
            $root.resize($display-h, $vw);
        } else {
            $root.init-plane(self.plane, y => $visible-top, x => 0,
                rows => $display-h, cols => $vw);
        }
        # Propagate absolute viewport to the card. reposition + resize
        # alone don't refresh abs-y/abs-x, and downstream consumers
        # (Selkie::Widget::Image uses abs position to decide when to
        # re-blit a sprixel) otherwise see stale coordinates when the
        # card moves. The card's own VBox.render will cascade this to
        # grandchildren via its layout-children pass.
        $root.set-viewport(
            abs-y => self.abs-y + $visible-top,
            abs-x => self.abs-x,
            rows  => $display-h,
            cols  => $vw,
        );
        $root.mark-dirty;
        $root.render;

        $y += $h;
        $last = $i;
    }

    # Park off-screen items via park() rather than plain reposition
    # so child Image widgets clean up their sprixels (avatars in
    # Cantina's AvatarList scroll out of view but their pixel data
    # would otherwise stay painted on the terminal).
    for ^@!items.elems -> $i {
        next if $i >= $first && $i <= $last;
        my $root = @!items[$i]<root>;
        $root.park if $root.plane;
    }

    self.clear-dirty;
}

# --- Navigation ---

method handle-event(Selkie::Event $ev --> Bool) {
    return True if self!check-keybinds($ev);
    return False unless @!items;

    if $ev.event-type ~~ KeyEvent {
        given $ev.id {
            when NCKEY_UP     { self!select-prev; return True }
            when NCKEY_DOWN   { self!select-next; return True }
            when NCKEY_HOME   { self.select-first; return True }
            when NCKEY_END    { self.select-last; return True }
            when NCKEY_PGUP   { return self!scroll-selected-page(-1); }
            when NCKEY_PGDOWN { return self!scroll-selected-page( 1); }
        }
    }

    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self!select-prev; return True }
            when NCKEY_SCROLL_DOWN { self!select-next; return True }
        }
        return True if self!dispatch-mouse-handlers($ev);
    }

    False;
}

#|( Delegate a one-page scroll to the selected card. Tries
    C<scroll-content-page-by(±1)> first so the card can use its OWN
    viewport size (a chat message's body is far smaller than the
    chat pane); falls back to C<scroll-content-by(±self.rows)> for
    legacy cards that only expose the absolute-delta API. Returns
    True (event handled) whenever a card is selected, even when the
    card doesn't support either method — the alternative would be
    falling through to cross-card navigation, which surprises users
    who expect PgDown to walk further into the current message.
    Always returning True keeps PgUp/PgDown's contract simple:
    "scroll inside if you can, otherwise nothing happens". )
method !scroll-selected-page(Int $direction --> Bool) {
    return False unless @!items;
    my $widget = @!items[$!selected]<widget>;
    return True unless $widget.defined;
    if $widget.^can('scroll-content-page-by') {
        $widget.scroll-content-page-by($direction);
        self.mark-dirty;
    } elsif $widget.^can('scroll-content-by') {
        $widget.scroll-content-by($direction * self.rows.Int);
        self.mark-dirty;
    }
    True;
}

method !select-next() {
    return unless @!items;
    if $!selected < @!items.end {
        $!selected++;
        self!recalc-scroll;
        self.mark-dirty;
        $!select-supplier.emit($!selected);
    }
}

method !select-prev() {
    return unless @!items;
    if $!selected > 0 {
        $!selected--;
        self!recalc-scroll;
        self.mark-dirty;
        $!select-supplier.emit($!selected);
    }
}

# --- Scroll calculation ---

method !recalc-scroll() {
    return unless @!items;
    my $vh = self.rows;
    return unless $vh > 0;

    $!selected = ($!selected max 0) min @!items.end;

    if $!selected < $!scroll-top {
        $!scroll-top = $!selected;
        return;
    }

    my $used = 0;
    for $!scroll-top .. $!selected -> $i {
        $used += @!items[$i]<height>;
    }
    return if $used <= $vh;

    my $remaining = $vh;
    my $new-top = $!selected;
    while $new-top > 0 {
        $remaining -= @!items[$new-top]<height>;
        last if $remaining <= 0;
        if @!items[$new-top - 1]<height> <= $remaining {
            $new-top--;
        } else {
            $new-top--;
            last;
        }
    }
    $!scroll-top = $new-top;
}
