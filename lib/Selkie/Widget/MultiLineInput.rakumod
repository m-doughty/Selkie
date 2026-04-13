=begin pod

=head1 NAME

Selkie::Widget::MultiLineInput - Multi-line text input with word-wrap and 2D cursor

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::MultiLineInput;
use Selkie::Sizing;

my $area = Selkie::Widget::MultiLineInput.new(
    sizing      => Sizing.fixed(1),    # grows up to max-lines as user types
    max-lines   => 6,
    placeholder => 'Type a message... (Ctrl+Enter to send)',
);

$area.on-submit.tap: -> $text { send-message($text); $area.clear };
$area.on-change.tap: -> $text { save-draft($text) };

=end code

=head1 DESCRIPTION

A multi-line text area with word-wrapping, a 2D cursor, and dynamic
height that grows as the user types (up to C<max-lines>). Plain C<Enter>
inserts a newline; C<Ctrl+Enter> submits.

The height auto-adjusts via C<desired-height>: if you pass
C<sizing => Sizing.fixed(1)>, the parent layout sees the widget's
desired height grow as content is added, bounded by C<max-lines>.

C<set-text-silent> updates the buffer without emitting C<on-change> —
use this from store subscriptions to avoid feedback loops.

=head1 EXAMPLES

=head2 Chat compose area

=begin code :lang<raku>

my $compose = Selkie::Widget::MultiLineInput.new(
    sizing      => Sizing.fixed(1),
    max-lines   => 5,
    placeholder => 'Type a message — Ctrl+Enter to send',
);
$compose.on-submit.tap: -> $text {
    if $text.chars > 0 {
        $app.store.dispatch('chat/send', :$text);
        $compose.clear;
    }
};

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::TextInput> — single-line variant
=item L<Selkie::Widget::TextStream> — append-only log (no editing)

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;
use Selkie::Sizing;

unit class Selkie::Widget::MultiLineInput does Selkie::Widget;

has @!lines = ('',);
has UInt $!cursor-row = 0;
has UInt $!cursor-col = 0;
has UInt $!scroll-y = 0;          # vertical scroll (visual rows)
has UInt $.max-lines = 6;
has Str $.placeholder is rw = '';
has Bool $!focused = False;
has Supplier $!submit-supplier = Supplier.new;
has Supplier $!change-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::MultiLineInput) {
    %args<focusable> //= True;
    callwith(|%args);
}

method text(--> Str) { @!lines.join("\n") }

method set-text(Str:D $t) {
    self!load-text($t);
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

# Programmatic text update without firing on-change. Use this from store
# subscriptions to avoid loops where the subscription emits a change which
# is then re-dispatched into the same store path.
method set-text-silent(Str:D $t) {
    self!load-text($t);
    self!update-sizing;
    self.mark-dirty;
}

method !load-text(Str:D $t) {
    @!lines = $t.split("\n").List;
    @!lines = ('',) unless @!lines;
    $!cursor-row = @!lines.end;
    $!cursor-col = @!lines[*-1].chars;
}

method clear() { self.set-text('') }

method on-submit(--> Supply) { $!submit-supplier.Supply }
method on-change(--> Supply) { $!change-supplier.Supply }

method set-focused(Bool $f) {
    $!focused = $f;
    self.mark-dirty;
}

method is-focused(--> Bool) { $!focused }

method desired-height(--> UInt) {
    my $visual = self!total-visual-rows;
    my UInt $h = $visual max 1;
    $h = $h min $!max-lines;
    $h;
}

method line-count(--> UInt) { @!lines.elems }
method cursor-row(--> UInt) { $!cursor-row }
method cursor-col(--> UInt) { $!cursor-col }

# --- Visual line wrapping ---

method !wrap-width(--> UInt) {
    self.cols max 1;
}

method !total-visual-rows(--> UInt) {
    my $w = self!wrap-width;
    my $total = 0;
    for @!lines -> $line {
        $total += ($line.chars / $w).ceiling max 1;
    }
    $total.UInt;
}

# Map logical (row, col) to visual row
method !cursor-visual-row(--> UInt) {
    my $w = self!wrap-width;
    my $vrow = 0;
    for ^$!cursor-row -> $i {
        $vrow += (@!lines[$i].chars / $w).ceiling max 1;
    }
    $vrow += ($!cursor-col / $w).floor;
    $vrow.UInt;
}

# Map logical (row, col) to visual col
method !cursor-visual-col(--> UInt) {
    my $w = self!wrap-width;
    ($!cursor-col % $w).UInt;
}

# Build array of visual lines (each is a substr of a logical line)
method !visual-lines(--> Array) {
    my $w = self!wrap-width;
    my @vlines;
    for @!lines -> $line {
        if $line.chars <= $w {
            @vlines.push($line);
        } else {
            my $pos = 0;
            while $pos < $line.chars {
                @vlines.push($line.substr($pos, $w));
                $pos += $w;
            }
        }
        # Empty lines still take a row
        @vlines.push('') if $line.chars == 0 && @vlines[*-1] ne '';
    }
    @vlines.Array;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my $style = $!focused ?? self.theme.input-focused !! self.theme.input;
    self.apply-style($style);

    my UInt $visible-rows = self.rows;
    my UInt $w = self.cols;

    # Fill background
    for ^$visible-rows -> $row {
        ncplane_putstr_yx(self.plane, $row, 0, ' ' x $w);
    }

    if @!lines.elems == 1 && @!lines[0].chars == 0 && !$!focused && $!placeholder.chars > 0 {
        my $ps = self.theme.input-placeholder;
        self.apply-style($ps);
        ncplane_putstr_yx(self.plane, 0, 0, $!placeholder.substr(0, $w));
    } else {
        self.apply-style($style);
        self!adjust-scroll;

        my @vlines = self!visual-lines;
        for ^$visible-rows -> $row {
            my UInt $vline-idx = $!scroll-y + $row;
            last if $vline-idx >= @vlines.elems;
            ncplane_putstr_yx(self.plane, $row, 0, @vlines[$vline-idx]);
        }

        # Draw cursor
        if $!focused {
            my Int $cursor-vrow = self!cursor-visual-row - $!scroll-y;
            my UInt $cursor-vcol = self!cursor-visual-col;
            if $cursor-vrow >= 0 && $cursor-vrow < $visible-rows {
                my $under = $!cursor-col < @!lines[$!cursor-row].chars
                    ?? @!lines[$!cursor-row].substr($!cursor-col, 1) !! ' ';
                ncplane_set_fg_rgb(self.plane, $style.bg // 0x1A1A2E);
                ncplane_set_bg_rgb(self.plane, $style.fg // 0xFFFFFF);
                ncplane_putstr_yx(self.plane, $cursor-vrow, $cursor-vcol, $under);
            }
        }
    }

    self.clear-dirty;
}

method !adjust-scroll() {
    my UInt $visible = self.rows max 1;
    my UInt $total-vrows = self!total-visual-rows;
    my UInt $cursor-vrow = self!cursor-visual-row;

    # Clamp scroll to valid range
    my $max-scroll = ($total-vrows - $visible) max 0;
    $!scroll-y = $!scroll-y min $max-scroll;

    # Ensure cursor is visible
    if $cursor-vrow < $!scroll-y {
        $!scroll-y = $cursor-vrow;
    } elsif $cursor-vrow >= $!scroll-y + $visible {
        $!scroll-y = $cursor-vrow - $visible + 1;
    }
}

method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $!focused;

    # Mouse scroll
    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self!move-up; return True }
            when NCKEY_SCROLL_DOWN { self!move-down; return True }
        }
        return False;
    }

    return False unless $ev.input-type == NCTYPE_PRESS || $ev.input-type == NCTYPE_REPEAT
                     || $ev.input-type == NCTYPE_UNKNOWN;

    # Ctrl+Enter submits; plain Enter inserts newline
    if $ev.id == NCKEY_ENTER {
        if $ev.has-modifier(Mod-Ctrl) {
            $!submit-supplier.emit(self.text);
            return True;
        } else {
            self!insert-newline;
            return True;
        }
    }

    # Let Ctrl/Alt/Super bubble for global keybinds (except Ctrl+Enter handled above)
    if $ev.has-modifier(Mod-Ctrl) || $ev.has-modifier(Mod-Alt) || $ev.has-modifier(Mod-Super) {
        return self!check-keybinds($ev);
    }

    given $ev.id {
        when NCKEY_BACKSPACE {
            self!do-backspace;
            return True;
        }
        when NCKEY_DEL {
            self!do-delete;
            return True;
        }
        when NCKEY_LEFT {
            self!move-left;
            return True;
        }
        when NCKEY_RIGHT {
            self!move-right;
            return True;
        }
        when NCKEY_UP {
            self!move-up;
            return True;
        }
        when NCKEY_DOWN {
            self!move-down;
            return True;
        }
        when NCKEY_HOME {
            $!cursor-col = 0;
            self.mark-dirty;
            return True;
        }
        when NCKEY_END {
            $!cursor-col = @!lines[$!cursor-row].chars;
            self.mark-dirty;
            return True;
        }
        default {
            if $ev.char.defined && $ev.char.chars == 1 {
                if $ev.char.ord == 10 || $ev.char.ord == 13 {
                    # Newline from paste
                    self!insert-newline;
                    return True;
                } elsif $ev.char.ord >= 32 {
                    self!insert-char($ev.char);
                    return True;
                }
            }
        }
    }
    False;
}

method !insert-char(Str $ch) {
    my $line = @!lines[$!cursor-row];
    @!lines[$!cursor-row] = $line.substr(0, $!cursor-col) ~ $ch ~ $line.substr($!cursor-col);
    $!cursor-col++;
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

method !insert-newline() {
    my $line = @!lines[$!cursor-row];
    my $before = $line.substr(0, $!cursor-col);
    my $after = $line.substr($!cursor-col);
    @!lines[$!cursor-row] = $before;
    @!lines.splice($!cursor-row + 1, 0, $after);
    $!cursor-row++;
    $!cursor-col = 0;
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

method !do-backspace() {
    if $!cursor-col > 0 {
        my $line = @!lines[$!cursor-row];
        @!lines[$!cursor-row] = $line.substr(0, $!cursor-col - 1) ~ $line.substr($!cursor-col);
        $!cursor-col--;
    } elsif $!cursor-row > 0 {
        my $prev = @!lines[$!cursor-row - 1];
        my $curr = @!lines[$!cursor-row];
        $!cursor-col = $prev.chars;
        @!lines[$!cursor-row - 1] = $prev ~ $curr;
        @!lines.splice($!cursor-row, 1);
        $!cursor-row--;
    } else {
        return;
    }
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

method !do-delete() {
    my $line = @!lines[$!cursor-row];
    if $!cursor-col < $line.chars {
        @!lines[$!cursor-row] = $line.substr(0, $!cursor-col) ~ $line.substr($!cursor-col + 1);
    } elsif $!cursor-row < @!lines.end {
        @!lines[$!cursor-row] = $line ~ @!lines[$!cursor-row + 1];
        @!lines.splice($!cursor-row + 1, 1);
    } else {
        return;
    }
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

method !move-left() {
    if $!cursor-col > 0 {
        $!cursor-col--;
    } elsif $!cursor-row > 0 {
        $!cursor-row--;
        $!cursor-col = @!lines[$!cursor-row].chars;
    }
    self.mark-dirty;
}

method !move-right() {
    if $!cursor-col < @!lines[$!cursor-row].chars {
        $!cursor-col++;
    } elsif $!cursor-row < @!lines.end {
        $!cursor-row++;
        $!cursor-col = 0;
    }
    self.mark-dirty;
}

method !move-up() {
    if $!cursor-row > 0 {
        $!cursor-row--;
        $!cursor-col = $!cursor-col min @!lines[$!cursor-row].chars;
    }
    self.mark-dirty;
}

method !move-down() {
    if $!cursor-row < @!lines.end {
        $!cursor-row++;
        $!cursor-col = $!cursor-col min @!lines[$!cursor-row].chars;
    }
    self.mark-dirty;
}

method !update-sizing() {
    my $h = self.desired-height;
    if self.sizing.mode ~~ SizeFixed && self.sizing.value != $h {
        self!set-sizing(Sizing.fixed($h));
        self.parent.mark-dirty if self.parent.defined;
    }
}
