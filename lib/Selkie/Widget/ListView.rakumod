=begin pod

=head1 NAME

Selkie::Widget::ListView - Scrollable single-select list of strings

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::ListView;
use Selkie::Sizing;

my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
$list.set-items(<Alpha Beta Gamma Delta>);

$list.on-select.tap:   -> $name { say "cursor on: $name" };
$list.on-activate.tap: -> $name { say "selected: $name" };
$list.on-key('d', -> $ { delete-item });

=end code

=head1 DESCRIPTION

A vertical list of string entries with a cursor. Arrow keys (and
PageUp/PageDown/Home/End/mouse wheel) move the cursor; C<Enter>
activates. The selected item is always fully visible; the list
auto-scrolls as the cursor moves.

Two Supplies:

=item C<on-select> — fires whenever the cursor moves. Use for "show details of highlighted"
=item C<on-activate> — fires when the user presses Enter. Use for "open this item"

Across C<set-items> calls, cursor position is preserved by label when
possible. If the previously-selected string is still in the new list,
the cursor follows it. Otherwise the cursor index is clamped to
bounds. Only resets to 0 when the list becomes empty.

Includes a scrollbar on the right edge when items exceed the viewport.

=head1 EXAMPLES

=head2 Store-driven list

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'file-list',
    -> $s { ($s.get-in('files') // []).map(*<name>).List },
    -> @items { $list.set-items(@items) },     # cursor preserved by value
    $list,
);

$list.on-activate.tap: -> $name {
    $app.store.dispatch('files/open', :$name);
};

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::CardList> — same pattern for variable-height cards
=item L<Selkie::Widget::RadioGroup> — similar UI but for one-of-many selection

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::ListView does Selkie::Widget;

has @!items;
has UInt $!cursor = 0;
has UInt $!scroll-offset = 0;
has Bool $.show-scrollbar = True;
has Supplier $!select-supplier = Supplier.new;
has Supplier $!activate-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::ListView) {
    %args<focusable> //= True;
    callwith(|%args);
}

submethod TWEAK() {
    # Single-click moves the cursor to the row under the pointer (same
    # semantics as Up/Down — selection only). Double-click activates,
    # matching the on-activate keyboard path (Enter). Clicks on the
    # scrollbar column fall through; scroll-wheel covers the common
    # navigation case for v1.
    self.on-click: -> $ev {
        my $row = self.local-row($ev);
        my $col = self.local-col($ev);
        if $row >= 0 && $col >= 0 {
            my UInt $vw = self.cols;
            my Bool $need-scrollbar = $!show-scrollbar && @!items.elems > self.rows;
            my UInt $content-w = $need-scrollbar ?? $vw - 1 !! $vw;
            if $col < $content-w {
                my $idx = $!scroll-offset + $row;
                if @!items && $idx < @!items.elems {
                    if $idx != $!cursor {
                        $!cursor = $idx;
                        self!ensure-visible;
                        self.mark-dirty;
                        $!select-supplier.emit(self.selected);
                    }
                    $!activate-supplier.emit(self.selected) if $ev.click-count >= 2;
                }
            }
        }
    };
}

method items(--> List) { @!items.List }
method cursor(--> UInt) { $!cursor }
method selected(--> Str) { @!items[$!cursor] // Str }

method on-select(--> Supply) { $!select-supplier.Supply }
method on-activate(--> Supply) { $!activate-supplier.Supply }

method set-items(@new-items) {
    # Preserve the cursor's relative position when possible. If the
    # previously-selected string is still in the new list, move the cursor
    # to its new index. Otherwise clamp to bounds. Avoids the surprising
    # "cursor jumps back to 0 every time the list is rebuilt" behaviour.
    my Str $prev-selected = @!items ?? (@!items[$!cursor] // Str) !! Str;

    @!items = @new-items;

    if @!items.elems == 0 {
        $!cursor = 0;
        $!scroll-offset = 0;
    } elsif $prev-selected.defined {
        my $found = @!items.first($prev-selected, :k);
        $!cursor = $found // ($!cursor min (@!items.elems - 1));
        self!ensure-visible;
    } else {
        $!cursor = $!cursor min (@!items.elems - 1);
        self!ensure-visible;
    }

    self.mark-dirty;
    $!select-supplier.emit(self.selected) if @!items;
}

method select-index(UInt $idx) {
    return unless @!items;
    $!cursor = $idx min (@!items.elems - 1);
    self!ensure-visible;
    self.mark-dirty;
    $!select-supplier.emit(self.selected);
}

method !ensure-visible() {
    my UInt $vh = self.rows max 1;
    if $!cursor < $!scroll-offset {
        $!scroll-offset = $!cursor;
    } elsif $!cursor >= $!scroll-offset + $vh {
        $!scroll-offset = $!cursor - $vh + 1;
    }
}

method !max-offset(--> UInt) {
    my UInt $vh = self.rows;
    @!items.elems > $vh ?? @!items.elems - $vh !! 0;
}

method render() {
    return without self.plane;

    my UInt $max = self!max-offset;
    $!scroll-offset = $max if $!scroll-offset > $max;

    ncplane_erase(self.plane);

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    my Bool $need-scrollbar = $!show-scrollbar && @!items.elems > $vh;
    my UInt $content-w = $need-scrollbar ?? $vw - 1 !! $vw;

    my $normal = self.theme.text;
    my $highlight = self.theme.text-highlight;
    my $base = self.theme.base;

    my UInt $visible = $vh min @!items.elems;
    for ^$visible -> $row {
        my UInt $idx = $!scroll-offset + $row;
        last if $idx >= @!items.elems;

        my $is-selected = $idx == $!cursor;
        my $style = $is-selected ?? $highlight !! $normal;

        # Selected line gets highlight bg, others get base bg
        if $is-selected {
            ncplane_set_fg_rgb(self.plane, $highlight.fg) if $highlight.fg.defined;
            ncplane_set_bg_rgb(self.plane, $base.bg // 0x1A1A2E);
            ncplane_set_styles(self.plane, $highlight.styles);
        } else {
            ncplane_set_fg_rgb(self.plane, $normal.fg) if $normal.fg.defined;
            ncplane_set_bg_rgb(self.plane, $base.bg // 0x1A1A2E) if $base.bg.defined;
            ncplane_set_styles(self.plane, 0);
        }

        my $text = @!items[$idx] // '';
        $text = $text.substr(0, $content-w) if $text.chars > $content-w;
        # Pad to full width for consistent background
        $text = $text ~ (' ' x ($content-w - $text.chars)) if $text.chars < $content-w;
        ncplane_putstr_yx(self.plane, $row, 0, $text);
    }

    self!render-scrollbar if $need-scrollbar;
    self.clear-dirty;
}

method !render-scrollbar() {
    my UInt $vh = self.rows;
    my UInt $sx = self.cols - 1;
    my $max = self!max-offset;
    return unless $max > 0;

    my $track-style = self.theme.scrollbar-track;
    my $thumb-style = self.theme.scrollbar-thumb;

    my Rat $thumb-ratio = $vh / @!items.elems;
    my UInt $thumb-h = ($vh * $thumb-ratio).ceiling.UInt max 1;
    my UInt $thumb-y = (($!scroll-offset / $max) * ($vh - $thumb-h)).floor.UInt;

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
    # Check widget keybinds first (e.g. 'a' for import) — works even with empty list
    if $ev.event-type ~~ KeyEvent {
        return True if self!check-keybinds($ev);
    }

    return False unless @!items;

    given $ev.id {
        when NCKEY_UP {
            if $!cursor > 0 {
                $!cursor--;
                self!ensure-visible;
                self.mark-dirty;
                $!select-supplier.emit(self.selected);
            }
            return True;
        }
        when NCKEY_DOWN {
            if $!cursor < @!items.elems - 1 {
                $!cursor++;
                self!ensure-visible;
                self.mark-dirty;
                $!select-supplier.emit(self.selected);
            }
            return True;
        }
        when NCKEY_PGUP {
            my $jump = self.rows max 1;
            $!cursor = $!cursor >= $jump ?? $!cursor - $jump !! 0;
            self!ensure-visible;
            self.mark-dirty;
            $!select-supplier.emit(self.selected);
            return True;
        }
        when NCKEY_PGDOWN {
            my $jump = self.rows max 1;
            $!cursor = ($!cursor + $jump) min (@!items.elems - 1);
            self!ensure-visible;
            self.mark-dirty;
            $!select-supplier.emit(self.selected);
            return True;
        }
        when NCKEY_HOME {
            $!cursor = 0;
            self!ensure-visible;
            self.mark-dirty;
            $!select-supplier.emit(self.selected);
            return True;
        }
        when NCKEY_END {
            $!cursor = @!items.elems - 1;
            self!ensure-visible;
            self.mark-dirty;
            $!select-supplier.emit(self.selected);
            return True;
        }
        when NCKEY_ENTER {
            $!activate-supplier.emit(self.selected);
            return True;
        }
    }

    # Mouse: scroll-wheel moves the cursor; click handlers registered
    # in TWEAK select / activate by row.
    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP {
                if $!cursor > 0 { $!cursor--; self!ensure-visible; self.mark-dirty; $!select-supplier.emit(self.selected) }
                return True;
            }
            when NCKEY_SCROLL_DOWN {
                if $!cursor < @!items.elems - 1 { $!cursor++; self!ensure-visible; self.mark-dirty; $!select-supplier.emit(self.selected) }
                return True;
            }
        }
        return True if self!dispatch-mouse-handlers($ev);
    }

    False;
}
