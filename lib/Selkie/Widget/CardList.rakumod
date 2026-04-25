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

method new(*%args) {
    %args<focusable> //= True;
    callwith(|%args);
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

    # Calculate top clip offset
    my $total-to-selected = 0;
    for $!scroll-top .. $!selected -> $i {
        $total-to-selected += @!items[$i]<height>;
    }
    my $top-clip = ($total-to-selected - $vh) max 0;

    # Render items
    my Int $y = 0 - $top-clip;
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
            when NCKEY_UP   { self!select-prev; return True }
            when NCKEY_DOWN { self!select-next; return True }
            when NCKEY_HOME { self.select-first; return True }
            when NCKEY_END  { self.select-last; return True }
        }
    }

    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self!select-prev; return True }
            when NCKEY_SCROLL_DOWN { self!select-next; return True }
        }
    }

    False;
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
