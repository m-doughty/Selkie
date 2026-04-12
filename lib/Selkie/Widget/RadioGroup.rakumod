use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::RadioGroup does Selkie::Widget;

has @!items;
has UInt $!cursor = 0;
has UInt $!selected = 0;
has UInt $!scroll-offset = 0;
has Bool $.show-scrollbar = True;
has Supplier $!change-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::RadioGroup) {
    %args<focusable> //= True;
    callwith(|%args);
}

method items(--> List) { @!items.List }
method cursor(--> UInt) { $!cursor }
method selected(--> UInt) { $!selected }
method selected-label(--> Str) { @!items[$!selected] // Str }

method on-change(--> Supply) { $!change-supplier.Supply }

method set-items(@new-items) {
    @!items = @new-items;
    $!cursor = 0;
    $!selected = 0;
    $!scroll-offset = 0;
    self.mark-dirty;
}

method select-index(UInt $idx) {
    return unless @!items;
    my UInt $clamped = $idx min (@!items.elems - 1);
    return if $clamped == $!selected;
    $!selected = $clamped;
    $!cursor = $clamped;
    self!ensure-visible;
    $!change-supplier.emit($!selected);
    self.mark-dirty;
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

        my Bool $is-cursor = $idx == $!cursor;
        my Bool $is-selected = $idx == $!selected;

        my $indicator = $is-selected ?? '(●)' !! '( )';
        my $text = "$indicator @!items[$idx]";
        $text = $text.substr(0, $content-w) if $text.chars > $content-w;
        $text = $text ~ (' ' x (($content-w - $text.chars) max 0));

        if $is-cursor {
            ncplane_set_fg_rgb(self.plane, $highlight.fg) if $highlight.fg.defined;
            ncplane_set_bg_rgb(self.plane, $base.bg // 0x1A1A2E);
            ncplane_set_styles(self.plane, $highlight.styles);
        } else {
            ncplane_set_fg_rgb(self.plane, $normal.fg) if $normal.fg.defined;
            ncplane_set_bg_rgb(self.plane, $base.bg // 0x1A1A2E) if $base.bg.defined;
            ncplane_set_styles(self.plane, 0);
        }

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
            }
            return True;
        }
        when NCKEY_DOWN {
            if $!cursor < @!items.elems - 1 {
                $!cursor++;
                self!ensure-visible;
                self.mark-dirty;
            }
            return True;
        }
        when NCKEY_PGUP {
            my $jump = self.rows max 1;
            $!cursor = $!cursor >= $jump ?? $!cursor - $jump !! 0;
            self!ensure-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_PGDOWN {
            my $jump = self.rows max 1;
            $!cursor = ($!cursor + $jump) min (@!items.elems - 1);
            self!ensure-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_HOME {
            $!cursor = 0;
            self!ensure-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_END {
            $!cursor = @!items.elems - 1;
            self!ensure-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_ENTER | NCKEY_SPACE {
            if $!cursor != $!selected {
                $!selected = $!cursor;
                $!change-supplier.emit($!selected);
                self.mark-dirty;
            }
            return True;
        }
    }

    # Mouse scroll
    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP {
                if $!cursor > 0 { $!cursor--; self!ensure-visible; self.mark-dirty }
                return True;
            }
            when NCKEY_SCROLL_DOWN {
                if $!cursor < @!items.elems - 1 { $!cursor++; self!ensure-visible; self.mark-dirty }
                return True;
            }
        }
    }

    False;
}
