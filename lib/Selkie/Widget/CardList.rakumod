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
=item C<:min-display-height> — smallest C<display-h> at which a partial render of this card is still
      meaningful. Non-selected cards whose visible height would fall below this threshold are
      parked rather than rendered as a sliver. Defaults to C<1> (any positive sliver renders, the
      pre-existing behaviour). Useful for cards with structural minimums — e.g. a chat card with a
      fixed-height avatar plus a name row plus a border edge needs at least C<avatar-rows + 2> rows
      before its partial render reads as "the bottom of a message" instead of "merged into the
      neighbour". The selected card is always exempt from this check; if it can't fully fit, the
      list relies on its own internal scrolling (e.g. a wrapped C<ScrollView>) to handle the
      overflow.

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
use Selkie::Widget::FocusableByDefault;
use Selkie::Widget::Border;
use Selkie::Event;
use Selkie::Sizing;

unit class Selkie::Widget::CardList does Selkie::Widget does Selkie::Widget::FocusableByDefault;

has @!items;        # Array of hashes: { widget, root, height, border? }
has Int $!selected = 0;
has Int $!scroll-top = 0;
has Supplier $!select-supplier = Supplier.new;


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

#| Supply that emits the new selected index whenever the selection
#| moves (Up / Down / mouse click / C<select-index> / C<select-first>
#| / C<select-last>). Does B<not> fire on C<add-item> or
#| C<clear-items> — those only mark-dirty.
method on-select(--> Supply) { $!select-supplier.Supply }

#| Index of the selected card. Stable across resizes / rebuilds. Returns
#| 0 when the list is empty (selection is conventionally at index 0
#| for empty lists; pair with C<count> if you need to disambiguate).
method selected(--> Int) { $!selected }

#| Number of cards in the list.
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
    self.reposition(self.park-y, 0) if self.plane;
    self!park-children(@!items.map(*.<root>));
}

#| The inner widget of the selected card (the C<$widget> argument
#| passed to C<add-item>), or C<Nil> when the list is empty / index
#| is out of range.
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

#|( Append a card. The four parameters describe the card's structure:
#|
#| C<$widget> — the inner widget the card represents. Returned by
#| C<selected-item>. Usually a C<RichText>, C<Text>, or custom widget;
#| does not need to manage its own plane (the C<:root> handles that).
#|
#| C<:root!> — the widget that gets a plane and is rendered. Often a
#| C<Border> wrapping the inner widget, or the inner widget itself if
#| no border is wanted. CardList drives reposition / resize / park on
#| this root each frame.
#|
#| C<:height!> — the card's logical height in cells. CardList uses
#| this to lay out cards stacked top-to-bottom and decide which fit
#| in the viewport. Variable-height cards are the whole point — every
#| card can have its own height.
#|
#| C<:border> — optional. When provided, CardList drives this widget's
#| C<set-has-focus> per render so the border highlights the selected
#| card regardless of where keyboard focus actually lives. Pass the
#| same Border instance you used as C<:root> to wire the highlight.
#|
#| C<:min-display-height> — when a card is partially clipped at the
#| top or bottom edge of the viewport, this is the minimum visible
#| height before CardList parks the card entirely instead of showing
#| a sliver. Default 1. )
method add-item($widget, :$root!, :$height!, :$border, UInt :$min-display-height = 1) {
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

    @!items.push({ :$widget, :$root, :$height, :$border, :$min-display-height });
    self.mark-dirty;
}

#| Destroy every card and reset selection / scroll. Calls C<destroy>
#| on each card's root, so any subscriptions or sprixels owned by
#| cards are cleaned up. Use before rebuilding the list to avoid
#| leaks; for incremental updates, prefer C<set-item-height> +
#| selective C<add-item>.
method clear-items() {
    for @!items -> %item {
        %item<root>.destroy if %item<root>.plane;
    }
    @!items = ();
    $!selected = 0;
    $!scroll-top = 0;
    self.mark-dirty;
}

#| Update an existing card's logical height (e.g. when its content
#| reflows after a viewport resize). No-op when C<$idx> is out of
#| range. Triggers re-layout on the next render.
method set-item-height(Int $idx, Int $height) {
    return unless $idx >= 0 && $idx < @!items.elems;
    @!items[$idx]<height> = $height;
    self.mark-dirty;
}

# --- Selection ---

#| Move the selection to C<$idx> (clamped to the valid range). Emits
#| on C<on-select>. No-op when the list is empty.
method select-index(Int $idx) {
    return unless @!items;
    $!selected = ($idx max 0) min @!items.end;
    self!recalc-scroll;
    self.mark-dirty;
    $!select-supplier.emit($!selected);
}

#| Jump selection to the last card. Useful after appending content in
#| chat-style consumers where the user wants to track the latest
#| message. Does B<not> emit on C<on-select> — symmetry with
#| C<select-first>.
method select-last() {
    return unless @!items;
    $!selected = @!items.end;
    self!recalc-scroll;
    self.mark-dirty;
}

#| Jump selection to the first card. Does B<not> emit on C<on-select>.
method select-first() {
    return unless @!items;
    $!selected = 0;
    self!recalc-scroll;
    self.mark-dirty;
}

#| Move selection one card up. Alias for the internal C<!select-prev>
#| so external callers can advance the cursor without registering a
#| keybind.
method scroll-up()   { self!select-prev }

#| Move selection one card down. See C<scroll-up>.
method scroll-down() { self!select-next }

# --- Rendering ---

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    return self.clear-dirty unless @!items && $vh > 0;

    self!recalc-scroll;

    # Sprixel ghost-prevention is the framework's responsibility now:
    # the post-render walk in L<Selkie::App> snapshots every
    # blit-plane-bearing widget (L<Selkie::Widget::Image> and any
    # custom equivalent) in the tree and drives the destroy → flush →
    # re-blit cycle for any whose snapshot changed. CardList just
    # lays out cards; the framework picks up any shifts from this
    # render's reposition / resize calls below.

    # Calculate top clip offset
    my $total-to-selected = 0;
    for $!scroll-top .. $!selected -> $i {
        $total-to-selected += @!items[$i]<height>;
    }
    my $top-clip = ($total-to-selected - $vh) max 0;

    # Leading park pre-pass: walk forward from scroll-top toward the
    # selected card and park any item whose post-clip remaining height
    # is below its declared min-display-height. Parking compacts the
    # layout — every parked card's full height is absorbed back into
    # the effective top-clip, so the cards that DO render slide upward
    # into the freed space rather than leaving a gap. Without this,
    # a card with display-h < min would render as a confusing sliver
    # (avatar + body bleeding through with no top border, "merging"
    # into the neighbour beneath); with it, the row range stays empty
    # and the visual separation between cards is preserved.
    #
    # Selection state is render-invariant: $!scroll-top is the
    # authoritative scroll position for navigation, and we never mutate
    # it from here. The pre-pass uses a render-local pair of effective
    # values that the rest of the layout pass reads from instead.
    my $effective-scroll-top = $!scroll-top;
    my $effective-top-clip   = $top-clip;
    while $effective-scroll-top < $!selected {
        my %item = @!items[$effective-scroll-top];
        my $h = %item<height>;
        my $remaining = $h - $effective-top-clip;
        my $min-h = %item<min-display-height> // 1;
        # Threshold is min(min-h, h): a card whose full height is
        # below its declared min-display-height (degenerate config —
        # e.g. a 5-row card declaring it needs 7 rows to be useful)
        # should still render at its full height rather than be
        # parked entirely. Practical cases — Cantina chat cards at
        # 8+ rows with min-h=7, system messages at 1+ rows with
        # min-h=1 — collapse to threshold = min-h.
        my $threshold = $min-h min $h;
        last if $remaining >= $threshold;
        my $root = %item<root>;
        $root.park if $root.plane;
        $effective-top-clip = ($effective-top-clip - $h) max 0;
        $effective-scroll-top++;
    }

    # Bottom anchor: when the visible items (effective-scroll-top
    # through end) don't fill the viewport, push them down so the last
    # item lands at the bottom edge instead of leaving empty space
    # below. The only legal scroll-top here is one where the whole tail
    # fits; if it didn't, recalc-scroll would have advanced scroll-top
    # already and total-from-scroll would equal the viewport.
    my $bottom-shift = 0;
    if $!bottom-anchor {
        my $total-from-scroll = 0;
        for $effective-scroll-top ..^ @!items.elems -> $i {
            $total-from-scroll += @!items[$i]<height>;
        }
        $bottom-shift = ($vh - $total-from-scroll) max 0;
    }

    # Render items
    my Int $y = $bottom-shift - $effective-top-clip;
    my Int $first = $effective-scroll-top;
    my Int $last = $effective-scroll-top - 1;

    for $effective-scroll-top ..^ @!items.elems -> $i {
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

        # Trailing park: a non-selected card past the focused row that
        # would render below its min-display-height threshold is parked
        # rather than drawn as a sliver. The selected card is always
        # exempt — recalc-scroll guarantees it fully fits unless it's
        # taller than the viewport, in which case both borders get
        # hidden and the wrapped ScrollView handles internal scrolling.
        # Threshold capped at the card's full height so a card too
        # short to ever satisfy its min-display-height still renders
        # in full (see leading pre-pass for the rationale).
        my $min-h = %item<min-display-height> // 1;
        my $threshold = $min-h min $h;
        if $i != $!selected && $display-h < $threshold {
            my $park-root = %item<root>;
            $park-root.park if $park-root.plane;
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
