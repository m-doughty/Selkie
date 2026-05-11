=begin pod

=head1 NAME

Selkie::Widget::ViewportedCardList - Row-scrolled selectable list of card widgets

=head1 DESCRIPTION

Like L<Selkie::Widget::CardList>, each item is an arbitrary widget with
a logical height and optional focus border. Unlike CardList, scrolling is
by content row: a viewport can start in the middle of any card.

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

has @!items;
has Int $!selected = 0;
has UInt $!scroll-offset = 0;
has UInt $!content-height = 0;
has Supplier $!select-supplier = Supplier.new;
has NcplaneHandle $!backing-plane;

has Bool $.show-scrollbar = True;
has Bool $.bottom-anchor = False;
has Bool $.follow-bottom = False;
has Bool $!follow-active = True;

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
    self.mark-dirty;
}

method set-item-height(Int $idx, Int $height) {
    return unless $idx >= 0 && $idx < @!items.elems;
    @!items[$idx]<height> = $height;
    self!update-content-height;
    self.scroll-to($!scroll-offset);
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

method scroll-to(UInt $row) {
    self!update-content-height;
    my UInt $max = self!max-offset;
    $!scroll-offset = $row min $max;
    $!follow-active = $!scroll-offset >= $max;
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

method render() {
    return without self.plane;
    ncplane_erase(self.plane);
    self!update-content-height;

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    my UInt $content-w = self!content-width;
    return self.clear-dirty unless @!items && $vh > 0 && $vw > 0 && $content-w > 0;

    my UInt $max = self!max-offset;
    if $!follow-bottom && $!follow-active {
        $!scroll-offset = $max;
    } else {
        $!scroll-offset = $!scroll-offset min $max;
        $!follow-active = True if $!scroll-offset >= $max;
    }

    self!ensure-backing-plane($!content-height max 1, $content-w);
    ncplane_erase($!backing-plane);

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
        $root.mark-dirty;
        $root.render;
        @visible.push($root);
        $cum-y = $end;
    }

    for @visible -> $root {
        self!merge-subtree($root);
    }
    ncplane_move_yx($!backing-plane, self.park-y, 0);
    self!render-scrollbar if $show-bar;
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

#|( Per-cell read+write loop using heap-stable primitives.

    Notcurses's C<ncplane_at_yx> returns a malloc'd C<char*> the caller
    is contractually obligated to free (see
    F<notcurses/doc/man/man3/notcurses_plane.3.md:512-514>); the Raku
    binding marshals it as C<Str> without freeing the underlying C
    buffer, so a hot per-cell loop over every cell of every visible
    widget per frame leaks a few bytes thousands of times a second.
    That's the exact pattern called out in
    F<memory/nativecall_str_free_trap.md>, so prefer the cell-based
    read here: C<ncplane_at_yx_cell> fills a caller-owned C<Nccell>
    (no malloc) and C<nccell_extended_gcluster> returns a pointer INTO
    the plane's existing egcpool (caller does NOT free).

    To preserve C<ncplane_at_yx>'s behaviour of substituting the
    plane's base cell when a position has an empty glyph (see
    F<src/lib/notcurses.c:250-264>), pre-fetch the base cell once per
    source plane and substitute its EGC / stylemask / channels when
    the read cell has an empty gcluster. Without this fallback,
    "interior" cells of a Border (the space inside the box) would not
    be copied to the destination plane and would show through to
    whatever was painted there before. )
method !copy-cells(
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
