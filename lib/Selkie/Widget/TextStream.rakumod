=begin pod

=head1 NAME

Selkie::Widget::TextStream - Append-only log with ring buffer and auto-scroll

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::TextStream;
use Selkie::Sizing;

my $log = Selkie::Widget::TextStream.new(
    sizing    => Sizing.flex,
    max-lines => 10_000,
);

$log.append('Starting up...');
$log.append('Connected', style => Selkie::Style.new(fg => 0x9ECE6A));

# Or drive from a Supply — each emission becomes a line
$log.start-supply($lines-from-somewhere);

=end code

=head1 DESCRIPTION

A scrollable log of text lines. Internally a ring buffer — bounded by
C<max-lines> — so it's safe to append from high-volume sources without
unbounded memory growth.

Auto-scrolls to the bottom on append while the user is "at the end"
(the default state). When the user scrolls up with arrow keys or the
mouse wheel, auto-scroll pauses until they scroll back to the bottom.

Arrow keys, Page Up/Down, Home/End, and the scroll wheel are handled
when the widget is focused.

=head1 EXAMPLES

=head2 A streaming chat view

Pipe every message in a store-held array into the stream:

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'message-log',
    -> $s { $s.get-in('messages') // [] },
    -> @msgs { $log.clear; $log.append(.<text>) for @msgs },
    $log,
);

=end code

=head2 Colour-coded log levels

=begin code :lang<raku>

$log.append("INFO  $line", style => Selkie::Style.new(fg => 0xC0C0C0));
$log.append("WARN  $line", style => Selkie::Style.new(fg => 0xFFCC00));
$log.append("ERROR $line", style => Selkie::Style.new(fg => 0xFF5555, bold => True));

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Text> — static styled block of text
=item L<Selkie::Widget::ScrollView> — generic virtual-scrolling container

=end pod

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

#| Maximum number of lines retained. Older lines are discarded as new
#| ones arrive (ring buffer). Defaults to 10,000.
has UInt $.max-lines = 10_000;

has @!lines;
has UInt $!head = 0;
has UInt $!count = 0;
has UInt $!scroll-offset = 0;
has Bool $!follow = True;

#| Whether to render the vertical scrollbar on the right edge when the
#| buffer is taller than the viewport.
has Bool $.show-scrollbar = True;

has Supplier $!input-supplier = Supplier.new;

submethod TWEAK() {
    # Click + drag on the scrollbar column drags the thumb. Same
    # proportional mapping as ScrollView. Dragging also disables
    # auto-follow (scroll-to does this for us via $!follow rebind),
    # which is the user-expected behaviour: "I dragged off the end,
    # don't snap back when new lines arrive".
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
            my $raw-row = $ev.y - self.abs-y;
            my $clamped = ($raw-row max 0) min (self.rows - 1).Int;
            self!scrollbar-jump-to-row($clamped.UInt);
        }
    };
}

method !scrollbar-jump-to-row(UInt $row) {
    my UInt $vh = self.rows;
    return unless $vh > 0;
    my UInt $max = self!max-offset;
    return unless $max > 0;
    my Rat $thumb-ratio = $vh / ($!count max 1);
    my UInt $thumb-h = ($vh * $thumb-ratio).ceiling.UInt max 1;
    my UInt $track = ($vh - $thumb-h) max 1;
    my UInt $clamped = $row min $track;
    self.scroll-to(($clamped * $max / $track).floor.UInt);
}

#| Number of lines currently in the buffer.
method logical-height(--> UInt) { $!count }

#| Tap this to get every line as it's appended. Useful for mirroring
#| output to an external sink (log file, network).
method supply(--> Supply) { $!input-supplier.Supply }

#|( Forward every value from a Supply into the stream, coerced to string
    and split on newlines. Convenience for piping LLM streams, subprocess
    output, etc. )
method start-supply(Supply $s) {
    $s.tap: -> $v { self.append($v.Str) };
}

#|( Append text. If the text contains newlines, each line becomes a
    separate buffer entry. The optional C<:style> decorates those lines
    without affecting the rest of the buffer. )
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

#| Scroll to a specific row (0 = top). Above the max offset is clamped.
#| Auto-follow is re-enabled when you scroll to the end.
method scroll-to(UInt $row) {
    my UInt $max = self!max-offset;
    $!scroll-offset = $row min $max;
    $!follow = $!scroll-offset >= $max;
    self.mark-dirty;
}

#| Scroll by a relative delta. Negative goes up, positive goes down.
method scroll-by(Int $delta) {
    my Int $new = $!scroll-offset + $delta;
    $new = $new max 0;
    self.scroll-to($new.UInt);
}

#| Jump to the top of the buffer. Disables auto-follow until the user
#| scrolls back to the end.
method scroll-to-start() { self.scroll-to(0) }

#| Jump to the bottom and re-enable auto-follow.
method scroll-to-end()   { self.scroll-to(self!max-offset); $!follow = True }

method !max-offset(--> UInt) {
    my UInt $vh = self.rows;
    $!count > $vh ?? $!count - $vh !! 0;
}

#| Empty the buffer and reset to the top.
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
        return True if self!dispatch-mouse-handlers($ev);
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
