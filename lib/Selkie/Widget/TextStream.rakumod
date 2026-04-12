use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::TextStream does Selkie::Widget;

class StyledLine {
    has Str $.text;
    has Selkie::Style $.style;
}

has UInt $.max-lines = 10_000;
has @!lines;
has UInt $!head = 0;           # ring buffer head (oldest entry)
has UInt $!count = 0;          # number of entries in buffer
has UInt $!scroll-offset = 0;
has Bool $!follow = True;      # auto-scroll to bottom on append
has Bool $.show-scrollbar = True;
has Supplier $!input-supplier = Supplier.new;

method logical-height(--> UInt) { $!count }

method supply(--> Supply) { $!input-supplier.Supply }

method start-supply(Supply $s) {
    $s.tap: -> $v { self.append($v.Str) };
}

method append(Str:D $text, Selkie::Style :$style) {
    my $s = $style // Selkie::Style;
    for $text.lines -> $line {
        self!push-line(StyledLine.new(:text($line), :style($s)));
    }
    if $!follow {
        $!scroll-offset = self!max-offset;
    }
    self.mark-dirty;
}

method !push-line(StyledLine $line) {
    if $!count < $!max-lines {
        @!lines.push($line);
        $!count++;
    } else {
        @!lines[$!head] = $line;
        $!head = ($!head + 1) % $!max-lines;
    }
}

method !line-at(UInt $idx --> StyledLine) {
    @!lines[($!head + $idx) % @!lines.elems];
}

method scroll-to(UInt $row) {
    my UInt $max = self!max-offset;
    $!scroll-offset = $row min $max;
    $!follow = $!scroll-offset >= $max;
    self.mark-dirty;
}

method scroll-by(Int $delta) {
    my Int $new = $!scroll-offset + $delta;
    $new = $new max 0;
    self.scroll-to($new.UInt);
}

method scroll-to-start() { self.scroll-to(0) }
method scroll-to-end()   { self.scroll-to(self!max-offset); $!follow = True }

method !max-offset(--> UInt) {
    my UInt $vh = self.rows;
    $!count > $vh ?? $!count - $vh !! 0;
}

method clear() {
    @!lines = ();
    $!head = 0;
    $!count = 0;
    $!scroll-offset = 0;
    $!follow = True;
    self.mark-dirty;
}

method render() {
    return without self.plane;

    # Clamp scroll offset to valid range (dimensions may have changed since last scroll)
    my UInt $max = self!max-offset;
    $!scroll-offset = $max if $!scroll-offset > $max;

    ncplane_erase(self.plane);

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    my UInt $content-w = $!show-scrollbar && $!count > $vh
                         ?? $vw - 1
                         !! $vw;

    my $base-style = self.theme.base;

    my UInt $visible = $vh min $!count;
    for ^$visible -> $row {
        my UInt $line-idx = $!scroll-offset + $row;
        last if $line-idx >= $!count;

        my $sl = self!line-at($line-idx);
        my $s = $sl.style.defined ?? $base-style.merge($sl.style) !! $base-style;
        self.apply-style($s);

        my $display = $sl.text;
        $display = $display.substr(0, $content-w) if $display.chars > $content-w;
        ncplane_putstr_yx(self.plane, $row, 0, $display);
    }

    self!render-scrollbar if $!show-scrollbar && $!count > $vh;
    self.clear-dirty;
}

method render-region(UInt :$offset, UInt :$height) {
    self.render;
}

method !render-scrollbar() {
    my UInt $vh = self.rows;
    my UInt $sx = self.cols - 1;
    my $max = self!max-offset;
    return unless $max > 0;

    my $track-style = self.theme.scrollbar-track;
    my $thumb-style = self.theme.scrollbar-thumb;

    my Rat $thumb-ratio = $vh / $!count;
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
    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self.scroll-by(-3); return True }
            when NCKEY_SCROLL_DOWN { self.scroll-by(3);  return True }
        }
    }
    if $ev.event-type ~~ KeyEvent {
        given $ev.id {
            when NCKEY_UP     { self.scroll-by(-1); return True }
            when NCKEY_DOWN   { self.scroll-by(1);  return True }
            when NCKEY_PGUP   { self.scroll-by(-self.rows.Int); return True }
            when NCKEY_PGDOWN { self.scroll-by(self.rows.Int);  return True }
            when NCKEY_HOME   { self.scroll-to-start; return True }
            when NCKEY_END    { self.scroll-to-end;   return True }
        }
    }
    self!check-keybinds($ev);
}
