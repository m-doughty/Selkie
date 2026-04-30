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

=head2 Mouse and selection

Click positions the caret. Drag selects across rows; the selection
range is rendered with reverse-video and respects word-wrap (the
highlight follows the wrapped layout, not raw offsets). Double-click
selects the word under the cursor; triple-click selects the entire
current logical line. Scroll-wheel moves the cursor up/down. Ctrl+A
selects everything; Ctrl+C / Ctrl+X emit on C<on-copy> / C<on-cut> and
(for cut) delete the selection. Backspace and Delete consume an active
selection if present; typing replaces it.

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
use Selkie::Widget::TextInput :words;

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
has Supplier $!copy-supplier = Supplier.new;
has Supplier $!cut-supplier = Supplier.new;

#|( Selection anchor in (logical-row, logical-col). C<-1> in $!sel-anchor-row
    means "no selection" — cursor is a bare caret. When >= 0 the
    selection covers the half-open range from C<min(anchor, cursor)>
    to C<max(anchor, cursor)>, walked across logical lines. )
has Int $!sel-anchor-row = -1;
has Int $!sel-anchor-col = 0;

method new(*%args --> Selkie::Widget::MultiLineInput) {
    %args<focusable> //= True;
    callwith(|%args);
}

submethod TWEAK() {
    # Click positions the caret. Double-click selects the word under
    # the cursor; triple-click selects the entire current logical
    # line (matches the per-row selection convention from text
    # editors). Drag extends the selection from the press anchor.
    self.on-click: -> $ev {
        my $vrow = self.local-row($ev);
        my $vcol = self.local-col($ev);
        if $vrow >= 0 && $vcol >= 0 {
            my ($lrow, $lcol) = self!visual-to-logical(($!scroll-y + $vrow).UInt, $vcol.UInt);
            given $ev.click-count {
                when 2 { self!select-word-at($lrow, $lcol) }
                when 3 { self!select-line-at($lrow) }
                default {
                    # Place the caret and clear any selection. Drag
                    # arms the anchor lazily on first motion — see
                    # the on-drag handler. Anchoring here would turn
                    # every post-click keystroke into a 1-char
                    # selection (cursor advances; anchor stays).
                    $!cursor-row = $lrow;
                    $!cursor-col = $lcol;
                    $!sel-anchor-row = -1;
                    self.mark-dirty;
                }
            }
        }
    };
    self.on-drag: -> $ev {
        my $raw-row = $ev.y - self.abs-y;
        my $raw-col = $ev.x - self.abs-x;
        # Clamp to the visible plane — drag captures keep us as the
        # target even when the cursor leaves our bounds. Beyond the
        # buffer's last visual row, !visual-to-logical pins to the
        # last line / last column for us.
        my $vrow = ($raw-row max 0) min (self.rows - 1);
        my $vcol = ($raw-col max 0) min (self.cols - 1);
        my ($lrow, $lcol) = self!visual-to-logical(($!scroll-y + $vrow).UInt, $vcol.UInt);
        unless $lrow == $!cursor-row && $lcol == $!cursor-col {
            # First motion of a drag: anchor at the press-time
            # cursor (row, col). Subsequent motions extend.
            if $!sel-anchor-row < 0 {
                $!sel-anchor-row = $!cursor-row.Int;
                $!sel-anchor-col = $!cursor-col.Int;
            }
            $!cursor-row = $lrow;
            $!cursor-col = $lcol;
            self.mark-dirty;
        }
    };
}

# --- Selection model -------------------------------------------------------

#|( True iff a selection is active (anchor differs from cursor).
    Bare caret returns False. )
method has-selection(--> Bool) {
    $!sel-anchor-row >= 0
        && ($!sel-anchor-row != $!cursor-row.Int
            || $!sel-anchor-col != $!cursor-col.Int);
}

#|( Returns the normalised selection range as a List of two pairs:
    C<(:row, :col)> for the start and C<(:row, :col)> for the end
    (half-open at end). Returns C<()> when no selection. )
method selection-range(--> List) {
    return ().List unless self.has-selection;
    my ($a-r, $a-c) = ($!sel-anchor-row, $!sel-anchor-col);
    my ($c-r, $c-c) = ($!cursor-row.Int, $!cursor-col.Int);
    if $a-r < $c-r || ($a-r == $c-r && $a-c <= $c-c) {
        return ({ :row($a-r), :col($a-c) }, { :row($c-r), :col($c-c) }).List;
    }
    ({ :row($c-r), :col($c-c) }, { :row($a-r), :col($a-c) }).List;
}

#|( The text currently selected, walking line by line. C<\n> joins
    successive logical lines. Empty string when no selection. )
method selected-text(--> Str) {
    return '' unless self.has-selection;
    my ($s, $e) = self.selection-range;
    if $s<row> == $e<row> {
        return @!lines[$s<row>].substr($s<col>, $e<col> - $s<col>);
    }
    my @parts;
    @parts.push: @!lines[$s<row>].substr($s<col>);
    for ($s<row> + 1 .. $e<row> - 1) -> $r {
        @parts.push: @!lines[$r];
    }
    @parts.push: @!lines[$e<row>].substr(0, $e<col>);
    @parts.join("\n");
}

#| Clear the active selection without moving the caret.
method clear-selection() {
    return unless $!sel-anchor-row >= 0;
    $!sel-anchor-row = -1;
    self.mark-dirty;
}

method on-copy(--> Supply) { $!copy-supplier.Supply }
method on-cut(--> Supply)  { $!cut-supplier.Supply }

method !select-word-at(UInt $row, UInt $col) {
    my $line = @!lines[$row];
    return unless $line.chars > 0;
    my $start = prev-word-pos($line, ($col + 1).Int);
    my $end   = next-word-pos($line, $col.Int);
    while $end > $start && !($line.substr($end - 1, 1) ~~ /\w/) {
        $end--;
    }
    return if $end == $start;
    $!sel-anchor-row = $row.Int;
    $!sel-anchor-col = $start;
    $!cursor-row = $row;
    $!cursor-col = $end.UInt;
    self.mark-dirty;
}

method !select-line-at(UInt $row) {
    return unless @!lines[$row].chars > 0;
    $!sel-anchor-row = $row.Int;
    $!sel-anchor-col = 0;
    $!cursor-row = $row;
    $!cursor-col = @!lines[$row].chars;
    self.mark-dirty;
}

method !select-all() {
    return unless @!lines.elems > 0 && self.text.chars > 0;
    $!sel-anchor-row = 0;
    $!sel-anchor-col = 0;
    $!cursor-row = @!lines.end.UInt;
    $!cursor-col = @!lines[*-1].chars.UInt;
    self.mark-dirty;
}

# Delete the active selection from the buffer, leaving the caret at
# the start of the (now-deleted) range. Returns True if deletion
# actually happened. Caller emits change / dirty.
method !delete-selection(--> Bool) {
    return False unless self.has-selection;
    my ($s, $e) = self.selection-range;
    if $s<row> == $e<row> {
        my $line = @!lines[$s<row>];
        @!lines[$s<row>] = $line.substr(0, $s<col>) ~ $line.substr($e<col>);
    } else {
        my $head = @!lines[$s<row>].substr(0, $s<col>);
        my $tail = @!lines[$e<row>].substr($e<col>);
        @!lines[$s<row>] = $head ~ $tail;
        @!lines.splice($s<row> + 1, $e<row> - $s<row>);
    }
    $!cursor-row = $s<row>.UInt;
    $!cursor-col = $s<col>.UInt;
    $!sel-anchor-row = -1;
    True;
}

# Set both cursor coords; either clear the selection (extend=False)
# or anchor at the previous cursor position (extend=True).
method !move-cursor(UInt $r, UInt $c, Bool $extend) {
    if $extend {
        if $!sel-anchor-row < 0 {
            $!sel-anchor-row = $!cursor-row.Int;
            $!sel-anchor-col = $!cursor-col.Int;
        }
    } else {
        $!sel-anchor-row = -1;
    }
    $!cursor-row = $r;
    $!cursor-col = $c;
    self.mark-dirty;
}

# Map a visual (vrow, vcol) to logical (row, col). When vrow runs
# past the last visual row, pins to the last line / last column —
# useful so a click in empty space below the buffer lands at the end.
method !visual-to-logical(UInt $vrow, UInt $vcol --> List) {
    my $w = self!wrap-width;
    my $vidx = 0;
    for @!lines.kv -> $r, $line {
        my $line-vrows = ($line.chars / $w).ceiling max 1;
        if $vidx + $line-vrows > $vrow {
            my $segment = $vrow - $vidx;
            my $col = ($segment * $w + $vcol) min $line.chars;
            return ($r.UInt, $col.UInt);
        }
        $vidx += $line-vrows;
    }
    (@!lines.end.UInt, @!lines[*-1].chars.UInt);
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
    $!sel-anchor-row = -1;
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

#|( Same shape as C<!visual-lines>, but each entry is a hash with
    C<logical-row>, C<logical-col-start>, C<text>. Used by the
    selection overlay to map visual rows back to logical (row, col)
    spans for highlighting. )
method !visual-rows(--> Array) {
    my $w = self!wrap-width;
    my @rows;
    for @!lines.kv -> $r, $line {
        if $line.chars == 0 {
            @rows.push({ :logical-row($r), :logical-col-start(0), :text('') });
        } elsif $line.chars <= $w {
            @rows.push({ :logical-row($r), :logical-col-start(0), :text($line) });
        } else {
            my $pos = 0;
            while $pos < $line.chars {
                @rows.push({
                    :logical-row($r),
                    :logical-col-start($pos),
                    :text($line.substr($pos, $w)),
                });
                $pos += $w;
            }
        }
    }
    @rows.Array;
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

        my @vrows = self!visual-rows;
        for ^$visible-rows -> $row {
            my UInt $vline-idx = $!scroll-y + $row;
            last if $vline-idx >= @vrows.elems;
            ncplane_putstr_yx(self.plane, $row, 0, @vrows[$vline-idx]<text>);
        }

        # Selection overlay: redraw cells in the selection range with
        # reverse-video. Walks the visible visual rows and computes
        # overlap per-row against the normalised selection bounds.
        if self.has-selection {
            my ($s, $e) = self.selection-range;
            ncplane_set_fg_rgb(self.plane, $style.bg // 0x1A1A2E);
            ncplane_set_bg_rgb(self.plane, $style.fg // 0xFFFFFF);
            for ^$visible-rows -> $row {
                my UInt $vline-idx = $!scroll-y + $row;
                last if $vline-idx >= @vrows.elems;
                my %vr = @vrows[$vline-idx];
                next if %vr<logical-row> < $s<row> || %vr<logical-row> > $e<row>;
                my $seg-start = %vr<logical-col-start>;
                my $seg-end   = $seg-start + %vr<text>.chars;
                my $hi-lo = %vr<logical-row> == $s<row> ?? max($s<col>, $seg-start) !! $seg-start;
                my $hi-hi = %vr<logical-row> == $e<row> ?? min($e<col>, $seg-end)   !! $seg-end;
                next unless $hi-hi > $hi-lo;
                my $start-col = $hi-lo - $seg-start;
                my $sel-text = %vr<text>.substr($start-col, $hi-hi - $hi-lo);
                ncplane_putstr_yx(self.plane, $row, $start-col, $sel-text);
            }
        }

        # Draw cursor (skipped while selection is active — the
        # reverse-video span already marks the active end).
        if $!focused && !self.has-selection {
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
    # Mouse routes through the registration API regardless of focus.
    if $ev.event-type ~~ MouseEvent {
        # Scroll-wheel keeps its existing cursor-driven semantics.
        given $ev.id {
            when NCKEY_SCROLL_UP   { self!move-up; return True }
            when NCKEY_SCROLL_DOWN { self!move-down; return True }
        }
        return True if self!dispatch-mouse-handlers($ev);
        return False;
    }

    return False unless $!focused;

    return False unless $ev.input-type == NCTYPE_PRESS || $ev.input-type == NCTYPE_REPEAT
                     || $ev.input-type == NCTYPE_UNKNOWN;

    my $shift = $ev.has-modifier(Mod-Shift);
    my $ctrl  = $ev.has-modifier(Mod-Ctrl);

    # Ctrl+Enter submits; plain Enter inserts newline (replacing
    # selection if any).
    if $ev.id == NCKEY_ENTER {
        if $ctrl {
            $!submit-supplier.emit(self.text);
            return True;
        } else {
            self!delete-selection;
            self!insert-newline;
            return True;
        }
    }

    # Ctrl-chord shortcuts that own selection / copy / cut. Handled
    # before the generic Ctrl-bubble-out so they don't fall through
    # to global keybinds. Match on id (case-insensitive) — char is
    # typically unset for ctrl chords outside the kitty-keyboard path.
    if $ctrl && !$ev.has-modifier(Mod-Alt) && !$ev.has-modifier(Mod-Super) {
        my $lower-id = $ev.id;
        $lower-id = $lower-id + 32 if $lower-id >= 'A'.ord && $lower-id <= 'Z'.ord;
        given $lower-id {
            when 'a'.ord { self!select-all; return True }
            when 'c'.ord {
                $!copy-supplier.emit(self.selected-text) if self.has-selection;
                return True;
            }
            when 'x'.ord {
                if self.has-selection {
                    $!cut-supplier.emit(self.selected-text);
                    self!delete-selection;
                    $!change-supplier.emit(self.text);
                    self!update-sizing;
                    self.mark-dirty;
                }
                return True;
            }
        }
    }

    # Let other Ctrl/Alt/Super bubble for global keybinds — *unless*
    # the OS keyboard layout already composed the modifier into a
    # different printable character (e.g. UK Mac Alt-3 → '#'). See
    # TextInput.handle-event for the full rationale.
    my $composed = $ev.char.defined && $ev.char.chars == 1
                && $ev.char.ord >= 32 && $ev.char.ord != $ev.id;
    if !$composed && ($ev.has-modifier(Mod-Ctrl) || $ev.has-modifier(Mod-Alt) || $ev.has-modifier(Mod-Super)) {
        return self!check-keybinds($ev);
    }

    given $ev.id {
        when NCKEY_BACKSPACE {
            if self.has-selection {
                self!delete-selection;
                $!change-supplier.emit(self.text);
                self!update-sizing;
                self.mark-dirty;
            } elsif $shift {
                self!do-word-backspace;
            } else {
                self!do-backspace;
            }
            return True;
        }
        when NCKEY_DEL {
            if self.has-selection {
                self!delete-selection;
                $!change-supplier.emit(self.text);
                self!update-sizing;
                self.mark-dirty;
            } else {
                self!do-delete;
            }
            return True;
        }
        when NCKEY_LEFT {
            self!handle-left($shift);
            return True;
        }
        when NCKEY_RIGHT {
            self!handle-right($shift);
            return True;
        }
        when NCKEY_UP {
            self!handle-up($shift);
            return True;
        }
        when NCKEY_DOWN {
            self!handle-down($shift);
            return True;
        }
        when NCKEY_HOME {
            self!set-cursor-extending($!cursor-row, 0, $shift);
            return True;
        }
        when NCKEY_END {
            self!set-cursor-extending($!cursor-row, @!lines[$!cursor-row].chars, $shift);
            return True;
        }
        default {
            if $ev.char.defined && $ev.char.chars == 1 {
                if $ev.char.ord == 10 || $ev.char.ord == 13 {
                    self!delete-selection;
                    self!insert-newline;
                    return True;
                } elsif $ev.char.ord >= 32 {
                    self!delete-selection;   # type-replaces-selection
                    self!insert-char($ev.char);
                    return True;
                }
            }
        }
    }
    False;
}

# --- Selection-aware cursor moves --------------------------------------

# Helper: position cursor and clear/extend selection in one call.
method !set-cursor-extending(UInt $r, UInt $c, Bool $extend) {
    self!move-cursor($r, $c, $extend);
}

method !handle-left(Bool $extend) {
    my $start-row = $!cursor-row;
    my $start-col = $!cursor-col;
    if $extend {
        # Shift+Left: word-jump (matches existing convention) AND
        # extend selection. Falls back to plain prev-cell at column 0.
        if $!cursor-col == 0 && $!cursor-row > 0 {
            my $r = $!cursor-row - 1;
            my $line = @!lines[$r];
            my $c = $line.chars > 0 ?? prev-word-pos($line, $line.chars).UInt !! 0;
            self!move-cursor($r, $c, True);
        } elsif $!cursor-col > 0 {
            my $line = @!lines[$!cursor-row];
            my $c = prev-word-pos($line, $!cursor-col.Int).UInt;
            self!move-cursor($!cursor-row, $c, True);
        }
        return;
    }
    # Plain Left: clear selection, step one cell back across line
    # boundaries.
    if $!cursor-col > 0 {
        self!move-cursor($!cursor-row, $!cursor-col - 1, False);
    } elsif $!cursor-row > 0 {
        my $r = $!cursor-row - 1;
        self!move-cursor($r, @!lines[$r].chars.UInt, False);
    } else {
        self.clear-selection;
    }
}

method !handle-right(Bool $extend) {
    if $extend {
        my $line = @!lines[$!cursor-row];
        if $!cursor-col >= $line.chars && $!cursor-row < @!lines.end {
            self!move-cursor(($!cursor-row + 1).UInt, 0, True);
        } elsif $!cursor-col < $line.chars {
            my $c = next-word-pos($line, $!cursor-col.Int).UInt;
            self!move-cursor($!cursor-row, $c, True);
        }
        return;
    }
    my $line = @!lines[$!cursor-row];
    if $!cursor-col < $line.chars {
        self!move-cursor($!cursor-row, $!cursor-col + 1, False);
    } elsif $!cursor-row < @!lines.end {
        self!move-cursor(($!cursor-row + 1).UInt, 0, False);
    } else {
        self.clear-selection;
    }
}

method !handle-up(Bool $extend) {
    if $!cursor-row > 0 {
        my $r = $!cursor-row - 1;
        my $c = $!cursor-col min @!lines[$r].chars;
        self!move-cursor($r, $c.UInt, $extend);
    } elsif !$extend {
        self.clear-selection;
    }
}

method !handle-down(Bool $extend) {
    if $!cursor-row < @!lines.end {
        my $r = $!cursor-row + 1;
        my $c = $!cursor-col min @!lines[$r].chars;
        self!move-cursor($r.UInt, $c.UInt, $extend);
    } elsif !$extend {
        self.clear-selection;
    }
}

method !insert-char(Str $ch) {
    my $line = @!lines[$!cursor-row];
    @!lines[$!cursor-row] = $line.substr(0, $!cursor-col) ~ $ch ~ $line.substr($!cursor-col);
    $!cursor-col++;
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

#|( Insert C<$text> at the current cursor position in one operation,
    splitting on C<\n> so multi-line pasted content lays across
    multiple buffer lines. Equivalent to typing each character in
    turn but with one buffer rebuild instead of one per char —
    O(n) total instead of O(n²). Used by the App's paste-batching
    drain loop. )
method insert-text(Str:D $text --> Nil) {
    return if $text.chars == 0;
    self!delete-selection;
    # Strip control chars except \n (\r is normalised to \n) and \t.
    my $norm = $text.subst(/\r\n|\r/, "\n", :g);
    $norm = $norm.subst(/<[\x[00]..\x[08]\x[0B]..\x[0C]\x[0E]..\x[1F]\x[7F]]>/, '', :g);

    my @parts = $norm.split("\n");
    my $first = @parts.shift;

    # Insert the first line's worth of text at the cursor.
    my $line = @!lines[$!cursor-row];
    @!lines[$!cursor-row] = $line.substr(0, $!cursor-col) ~ $first ~ $line.substr($!cursor-col);
    $!cursor-col += $first.chars;

    # For each subsequent newline-separated chunk: split the current
    # line at the cursor, drop the chunk in as the next line, and
    # carry the tail along. After the loop the cursor lands at the
    # end of whatever the LAST chunk was.
    if @parts {
        my $tail = @!lines[$!cursor-row].substr($!cursor-col);
        @!lines[$!cursor-row] = @!lines[$!cursor-row].substr(0, $!cursor-col);
        for @parts.kv -> $i, $part {
            my $is-last = $i == @parts.end;
            my $row-text = $is-last ?? ($part ~ $tail) !! $part;
            @!lines.splice($!cursor-row + 1, 0, $row-text);
            $!cursor-row++;
            $!cursor-col = $part.chars;
        }
    }

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

#|( Shift-Left: jump to the start of the current or previous word.
    When the cursor is at column 0, the jump crosses the line
    boundary and lands at the start of the last word on the
    previous line (or column 0 of that line if the previous line
    is empty). )
method !move-word-left() {
    if $!cursor-col == 0 {
        return unless $!cursor-row > 0;
        $!cursor-row--;
        my $line = @!lines[$!cursor-row];
        $!cursor-col = $line.chars > 0 ?? prev-word-pos($line, $line.chars).UInt !! 0;
    } else {
        my $line = @!lines[$!cursor-row];
        $!cursor-col = prev-word-pos($line, $!cursor-col.Int).UInt;
    }
    self.mark-dirty;
}

#|( Shift-Right: jump to the start of the next word. When the cursor
    is at the end of the current line, the jump crosses to column 0
    of the next line. )
method !move-word-right() {
    my $line = @!lines[$!cursor-row];
    if $!cursor-col >= $line.chars {
        return unless $!cursor-row < @!lines.end;
        $!cursor-row++;
        $!cursor-col = 0;
    } else {
        $!cursor-col = next-word-pos($line, $!cursor-col.Int).UInt;
    }
    self.mark-dirty;
}

#|( Shift-Backspace: delete from the cursor back to the previous word
    boundary. At column 0, falls through to the regular backspace
    semantics so the line above is joined — matches what users
    expect from "delete previous word" in editors that also support
    multi-line. )
method !do-word-backspace() {
    if $!cursor-col == 0 {
        self!do-backspace;
        return;
    }
    my $line = @!lines[$!cursor-row];
    my $start = prev-word-pos($line, $!cursor-col.Int);
    return unless $start < $!cursor-col;
    @!lines[$!cursor-row] = $line.substr(0, $start) ~ $line.substr($!cursor-col);
    $!cursor-col = $start.UInt;
    $!change-supplier.emit(self.text);
    self!update-sizing;
    self.mark-dirty;
}

method !update-sizing() {
    my $h = self.desired-height;
    if self.sizing.mode ~~ SizeFixed && self.sizing.value != $h {
        self.set-sizing(Sizing.fixed($h));
        # Mark parent dirty so the next render re-runs its
        # layout-children with our new sizing. mark-dirty propagates
        # up to the root; render-children cascades back down so
        # every sibling gets a fresh layout pass. One top-down
        # traversal per frame is all we need — Selkie's handle-resize
        # doesn't recurse on its own (as of the layout-cascade
        # simplification), so there's no longer any "stale sizes
        # between handle-resize and render" window to worry about.
        self.parent.mark-dirty if self.parent.defined;
    }
}
