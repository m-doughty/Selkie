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

=end code

=head1 DESCRIPTION

A container that renders only the rows of its children currently in
view. Children report their C<logical-height>; ScrollView uses this to
compute scrollable extent and render the correct slice via
C<render-region>.

Arrow keys, PageUp/PageDown, Home/End, and the mouse wheel scroll when
the widget is focused. A scrollbar appears on the right edge when
content is taller than the viewport.

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

method scroll-offset(--> UInt) { $!scroll-offset }
method content-height(--> UInt) { $!content-height }
method viewport-height(--> UInt) { self.rows }

method scroll-to(UInt $row) {
    my UInt $max = self!max-offset;
    $!scroll-offset = $row min $max;
    self.mark-dirty;
}

method scroll-by(Int $delta) {
    my Int $new = $!scroll-offset + $delta;
    $new = $new max 0;
    self.scroll-to($new.UInt);
}

method scroll-to-start() { self.scroll-to(0) }

method scroll-to-end() { self.scroll-to(self!max-offset) }

method at-end(--> Bool) { $!scroll-offset >= self!max-offset }

method !max-offset(--> UInt) {
    my UInt $vh = self.rows;
    $!content-height > $vh ?? $!content-height - $vh !! 0;
}

method !update-content-height() {
    $!content-height = 0;
    for self.children -> $child {
        if $child.can('logical-height') {
            $!content-height += $child.logical-height;
        } elsif $child.sizing.mode ~~ SizeFixed {
            $!content-height += $child.sizing.value.UInt;
        } else {
            $!content-height += $child.rows;
        }
    }
}

method render() {
    return without self.plane;
    self!update-content-height;
    ncplane_erase(self.plane);

    my UInt $viewport-h = self.rows;
    my UInt $content-w = $!show-scrollbar && $!content-height > $viewport-h
                         ?? self.cols - 1
                         !! self.cols;

    # Virtual scroll: only render visible children
    my UInt $cum-y = 0;
    for self.children -> $child {
        my UInt $child-h = $child.can('logical-height')
            ?? $child.logical-height
            !! ($child.sizing.mode ~~ SizeFixed ?? $child.sizing.value.UInt !! $child.rows);
        my UInt $child-end = $cum-y + $child-h;

        if $child-end <= $!scroll-offset || $cum-y >= $!scroll-offset + $viewport-h {
            # Entirely outside viewport — hide plane
            $child.reposition($viewport-h, 0) if $child.plane;  # move offscreen
        } else {
            # Partially or fully visible
            my UInt $visible-start = ($!scroll-offset max $cum-y) - $cum-y;
            my Int $screen-y = ($cum-y - $!scroll-offset).Int;
            $screen-y = $screen-y max 0;

            my UInt $visible-rows = ($child-h - $visible-start) min ($viewport-h - $screen-y);

            if $child.plane {
                $child.reposition($screen-y.UInt, 0);
                $child.resize($visible-rows, $content-w);
            } else {
                $child.init-plane(self.plane,
                    y => $screen-y.UInt, x => 0, rows => $visible-rows, cols => $content-w);
            }

            if $child.can('render-region') {
                $child.render-region(offset => $visible-start, height => $visible-rows);
            } else {
                $child.render;
            }
        }
        $cum-y = $child-end;
    }

    self!render-scrollbar if $!show-scrollbar && $!content-height > $viewport-h;
    self.clear-dirty;
}

method !render-scrollbar() {
    my UInt $vh = self.rows;
    my UInt $sx = self.cols - 1;

    my $track-style = self.theme.scrollbar-track;
    my $thumb-style = self.theme.scrollbar-thumb;

    # Calculate thumb position and size
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
    # Check registered keybinds first (allows overriding default scroll behavior)
    return True if self!check-keybinds($ev);

    # Default scroll handling
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
    False;
}
