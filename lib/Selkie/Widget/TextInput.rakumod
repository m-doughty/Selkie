=begin pod

=head1 NAME

Selkie::Widget::TextInput - Single-line text input with cursor and editing

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::TextInput;
use Selkie::Sizing;

my $input = Selkie::Widget::TextInput.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Search...',
);

$input.on-submit.tap: -> $text { run-search($text) };
$input.on-change.tap: -> $text { update-preview($text) };

# Password field: mask characters
my $pw = Selkie::Widget::TextInput.new(
    sizing    => Sizing.fixed(1),
    mask-char => '•',
);

=end code

=head1 DESCRIPTION

A one-line text input. Arrow keys, Home, End, Backspace, and Delete
behave as you'd expect. Characters wider than the visible width
horizontally scroll the view to follow the cursor.

Four Supplies:

=item C<on-submit> — fires once when the user presses Enter, carrying the current text
=item C<on-change> — fires on every keystroke that modifies the buffer
=item C<on-copy> — fires on Ctrl+C, carrying the currently-selected text
=item C<on-cut> — fires on Ctrl+X, carrying the cut text (which is also deleted from the buffer)

For programmatic updates that shouldn't re-dispatch (e.g. syncing from
a store subscription), use C<set-text-silent> — it updates the buffer
without emitting on C<on-change>.

=head2 Mouse and selection

Click positions the caret. Drag selects from the press point to the
current cursor cell — the selection range is rendered with reverse-video.
Double-click selects the word under the cursor; triple-click selects
the entire buffer. C<has-selection>, C<selection-range>, and
C<selected-text> expose the current selection state.

Keyboard cooperates: Shift+Left / Shift+Right jump by word AND extend
the selection (the legacy word-jump is now also a selection-extend);
plain arrows clear any selection before moving. Ctrl+A selects all.
Ctrl+C and Ctrl+X emit on the corresponding supplies — Selkie does
not own the system clipboard, so apps wire OSC 52 / notcurses paste-buffer
in their handlers. Backspace and Delete delete an active selection if
present; typing replaces it.

=head2 Modifier bubbling

Modified keys (Ctrl, Alt, Super) bubble past the input so global
keybinds still work — except for Ctrl+A / C / X (selection-related,
handled internally) and except when the OS keyboard layout has already
composed the modifier into a different printable character (e.g. UK Mac
Alt-3 → C<#>, US Mac Alt-2 → C<™>). In that case the composed character
is treated as typed input, since blocking it would make those characters
untypeable on layouts that need a modifier to produce them. Bare
characters are consumed for typing.

=head1 EXAMPLES

=head2 Store-synced input

=begin code :lang<raku>

$app.store.subscribe-with-callback(
    'sync-name',
    -> $s { ($s.get-in('form', 'name') // '').Str },
    -> $v { $name-input.set-text-silent($v) if $name-input.text ne $v },
    $name-input,
);
$name-input.on-change.tap: -> $v {
    $app.store.dispatch('form/set', field => 'name', value => $v);
};

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::MultiLineInput> — multi-line variant with word wrap
=item L<Selkie::Widget::Button> — for commit-only actions

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::TextInput does Selkie::Widget;

#|( Find the position of the start of the next word at or after C<$pos>
    in C<$s>. Word = run of C<\w> chars. Skips through the current
    char's class (word or non-word), then through any trailing
    non-word chars, landing at the first word char of the next word
    — or C<$s.chars> if there is no next word. Used by shift-right
    word-jump and by C<MultiLineInput>'s 2D variant. )
sub next-word-pos(Str:D $s, Int:D $pos --> Int) is export(:words) {
    my $len = $s.chars;
    my $i = $pos max 0;
    return $len if $i >= $len;
    my $is-word = $s.substr($i, 1) ~~ /\w/;
    while $i < $len && (($s.substr($i, 1) ~~ /\w/) ?? True !! False) == ($is-word ?? True !! False) {
        $i++;
    }
    while $i < $len && !($s.substr($i, 1) ~~ /\w/) {
        $i++;
    }
    $i;
}

#|( Find the position of the start of the previous word at or before
    C<$pos> in C<$s>. Skips backwards through any non-word chars,
    then backwards through word chars, landing on the index of the
    first char of that word — or 0 if we walked off the start. Used
    by shift-left and shift-backspace. )
sub prev-word-pos(Str:D $s, Int:D $pos --> Int) is export(:words) {
    my $i = $pos - 1;
    return 0 if $i <= 0;
    while $i > 0 && !($s.substr($i, 1) ~~ /\w/) {
        $i--;
    }
    while $i > 0 && ($s.substr($i - 1, 1) ~~ /\w/) {
        $i--;
    }
    $i;
}

has Str $!buffer = '';
has UInt $!cursor = 0;
has UInt $!scroll-x = 0;    # horizontal scroll for long input

#|( Selection anchor offset. -1 means "no selection" — the cursor is a
    bare caret. When >= 0, the selection covers the half-open range
    from C<min(anchor, cursor)> to C<max(anchor, cursor)>. The cursor
    is the movable end; the anchor stays put while extending. )
has Int $!sel-anchor = -1;

has Str $.placeholder is rw = '';
has Str $.mask-char;
has Supplier $!submit-supplier = Supplier.new;
has Supplier $!change-supplier = Supplier.new;
has Supplier $!copy-supplier = Supplier.new;
has Supplier $!cut-supplier = Supplier.new;
has Bool $!focused = False;

method new(*%args --> Selkie::Widget::TextInput) {
    %args<focusable> //= True;
    callwith(|%args);
}

submethod TWEAK() {
    # Click positions the caret; double-click selects the word under
    # the cursor; triple-click selects the entire buffer. Drag extends
    # the selection from the press anchor to the current cursor cell.
    self.on-click: -> $ev {
        my $col = self.local-col($ev);
        if $col >= 0 {
            my $offset = ($!scroll-x + $col).UInt min $!buffer.chars;
            given $ev.click-count {
                when 2 {
                    self!select-word-at($offset);
                }
                when 3 {
                    self!select-all;
                }
                default {
                    # Place the caret and clear any selection. We do
                    # NOT pre-arm the anchor here — that would make
                    # subsequent typing produce a spurious 1-char
                    # selection (cursor advances on insert, anchor
                    # stays put, the next keystroke would replace).
                    # Drag arms the anchor lazily on first motion.
                    $!cursor = $offset;
                    $!sel-anchor = -1;
                    self.mark-dirty;
                }
            }
        }
    };
    self.on-drag: -> $ev {
        # Allow drag past the visible edge by clamping the local-col;
        # the existing scroll machinery takes care of the rest on the
        # next render. local-col returns -1 for out-of-bounds, but
        # drag captures keep us as the target — recompute against the
        # raw event.x so the caret tracks the cursor outside our cell.
        my $raw-col = $ev.x - self.abs-x;
        my $clamped = ($raw-col max 0) min (self.cols - 1);
        my $offset = ($!scroll-x + $clamped).UInt min $!buffer.chars;
        if $offset != $!cursor {
            # First motion of a drag: anchor at the press-time cursor
            # position. Subsequent motions extend the selection from
            # that anchor.
            $!sel-anchor = $!cursor.Int if $!sel-anchor < 0;
            $!cursor = $offset;
            self.mark-dirty;
        }
    };
}

method text(--> Str) { $!buffer }

#|( True iff there is an active selection (anchor differs from cursor).
    A bare caret returns False. )
method has-selection(--> Bool) {
    $!sel-anchor >= 0 && $!sel-anchor != $!cursor.Int;
}

#|( Half-open offset range of the current selection, normalised to
    C<low..^high>. Returns C<0..^0> when there's no selection. )
method selection-range(--> Range) {
    return 0..^0 unless self.has-selection;
    my $a = $!sel-anchor;
    my $c = $!cursor.Int;
    ($a min $c) ..^ ($a max $c);
}

#| The substring currently selected, or the empty string when there
#| is no selection.
method selected-text(--> Str) {
    return '' unless self.has-selection;
    my $r = self.selection-range;
    $!buffer.substr($r.min, $r.max - $r.min);
}

#| Clear any active selection without moving the caret.
method clear-selection() {
    return unless $!sel-anchor >= 0;
    $!sel-anchor = -1;
    self.mark-dirty;
}

#|( Supply emitting the currently-selected text on Ctrl+C. The Selkie
    framework does not own the system clipboard — apps wire this up
    themselves via OSC 52 or notcurses paste-buffer. The supply only
    fires when there's an active selection. )
method on-copy(--> Supply) { $!copy-supplier.Supply }

#|( Supply emitting on Ctrl+X. Like on-copy but the selection is also
    deleted from the buffer. )
method on-cut(--> Supply) { $!cut-supplier.Supply }

method !select-word-at(UInt $offset) {
    my $start = prev-word-pos($!buffer, ($offset + 1).Int);
    my $end   = next-word-pos($!buffer, $offset.Int);
    # Trim trailing non-word chars next-word-pos lands on.
    while $end > $start && !($!buffer.substr($end - 1, 1) ~~ /\w/) {
        $end--;
    }
    return if $end == $start;
    $!sel-anchor = $start;
    $!cursor = $end.UInt;
    self.mark-dirty;
}

method !select-all() {
    return unless $!buffer.chars > 0;
    $!sel-anchor = 0;
    $!cursor = $!buffer.chars;
    self.mark-dirty;
}

# Delete the active selection from the buffer, leaving the caret at
# the start of the (now-deleted) range. Returns True if a selection
# was deleted. Caller handles change-supplier emission & dirty flag.
method !delete-selection(--> Bool) {
    return False unless self.has-selection;
    my $r = self.selection-range;
    $!buffer = $!buffer.substr(0, $r.min) ~ $!buffer.substr($r.max);
    $!cursor = $r.min.UInt;
    $!sel-anchor = -1;
    True;
}

# Set the cursor while either clearing or extending the selection
# based on whether Shift is held. Used by every cursor-move keybind
# so the per-direction handlers stay terse.
method !move-cursor(UInt $new, Bool $extend-selection) {
    if $extend-selection {
        $!sel-anchor = $!cursor.Int if $!sel-anchor < 0;
    } else {
        $!sel-anchor = -1;
    }
    $!cursor = $new;
    self.mark-dirty;
}

method set-text(Str:D $t) {
    $!buffer = $t;
    $!cursor = $t.chars;
    $!sel-anchor = -1;
    $!change-supplier.emit($!buffer);
    self.mark-dirty;
}

method set-text-silent(Str:D $t) {
    $!buffer = $t;
    $!cursor = $t.chars;
    $!sel-anchor = -1;
    self.mark-dirty;
}

method clear() { self.set-text('') }

method on-submit(--> Supply) { $!submit-supplier.Supply }
method on-change(--> Supply) { $!change-supplier.Supply }

method set-focused(Bool $f) {
    $!focused = $f;
    self.mark-dirty;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my $style = $!focused ?? self.theme.input-focused !! self.theme.input;
    self.apply-style($style);

    # Fill background
    my UInt $w = self.cols;
    ncplane_putstr_yx(self.plane, 0, 0, ' ' x $w);

    if $!buffer.chars == 0 && !$!focused && $!placeholder.chars > 0 {
        my $ps = self.theme.input-placeholder;
        self.apply-style($ps);
        my $display = $!placeholder.substr(0, $w);
        ncplane_putstr_yx(self.plane, 0, 0, $display);
    } else {
        self.apply-style($style);
        # Ensure cursor is visible
        self!adjust-scroll;
        my $display-buf = $!mask-char.defined
            ?? $!mask-char x $!buffer.chars
            !! $!buffer;
        my $visible = $display-buf.substr($!scroll-x, $w);
        ncplane_putstr_yx(self.plane, 0, 0, $visible);

        # Selection overlay: redraw cells in the selection range with
        # reverse-video. Cheap (one substr per visible run) and keeps
        # the base render code unchanged for the no-selection path.
        if self.has-selection {
            my $r = self.selection-range;
            my $vis-start = $r.min - $!scroll-x;
            my $vis-end   = $r.max - $!scroll-x;
            $vis-start = 0 if $vis-start < 0;
            $vis-end   = $w if $vis-end > $w;
            if $vis-end > $vis-start {
                ncplane_set_fg_rgb(self.plane, $style.bg // 0x1A1A2E);
                ncplane_set_bg_rgb(self.plane, $style.fg // 0xFFFFFF);
                my $sel-text = $display-buf.substr($!scroll-x + $vis-start, $vis-end - $vis-start);
                ncplane_putstr_yx(self.plane, 0, $vis-start, $sel-text);
            }
        }

        # Draw caret (only when the cursor is NOT inside the selection
        # — the selection's reverse-video already marks the active end).
        if $!focused && !self.has-selection {
            my UInt $cx = $!cursor - $!scroll-x;
            my $under = $!cursor < $display-buf.chars
                ?? $display-buf.substr($!cursor, 1) !! ' ';
            ncplane_set_fg_rgb(self.plane, $style.bg // 0x1A1A2E);
            ncplane_set_bg_rgb(self.plane, $style.fg // 0xFFFFFF);
            ncplane_putstr_yx(self.plane, 0, $cx, $under);
        }
    }

    self.clear-dirty;
}

method !adjust-scroll() {
    my UInt $w = self.cols;
    if $!cursor < $!scroll-x {
        $!scroll-x = $!cursor;
    } elsif $!cursor >= $!scroll-x + $w {
        $!scroll-x = $!cursor - $w + 1;
    }
}

#|( Insert C<$text> at the current cursor position in one operation.
    Equivalent to typing each character in turn, but does ONE buffer
    concat instead of one per char — drops paste cost from O(n²) to
    O(n). Newlines and other control chars in C<$text> are stripped
    (single-line input). Used by the App's paste-batching drain loop;
    application code can call it directly to programmatically
    insert text.

    If a selection is active, it is replaced (deleted then the new
    text is inserted at the deletion point) — matches the canonical
    "type to overwrite selection" behavior of every text editor. )
method insert-text(Str:D $text --> Nil) {
    my $clean = $text.subst(/\n/, '', :g).subst(/<[\x[00]..\x[1F]\x[7F]]>/, '', :g);
    return if $clean.chars == 0;
    self!delete-selection;
    $!buffer = $!buffer.substr(0, $!cursor) ~ $clean ~ $!buffer.substr($!cursor);
    $!cursor += $clean.chars;
    $!change-supplier.emit($!buffer);
    self.mark-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    # Mouse routes through the registration API regardless of focus —
    # App's click-to-focus has already promoted us on press.
    if $ev.event-type ~~ MouseEvent {
        return True if self!dispatch-mouse-handlers($ev);
        return False;
    }

    return False unless $!focused;
    return False unless $ev.input-type == NCTYPE_PRESS || $ev.input-type == NCTYPE_REPEAT
                     || $ev.input-type == NCTYPE_UNKNOWN;

    my $shift = $ev.has-modifier(Mod-Shift);
    my $ctrl  = $ev.has-modifier(Mod-Ctrl);

    # Ctrl-chord shortcuts that own selection / copy / cut. Handled
    # before the generic Ctrl-bubble-out below so they don't fall
    # through to global keybinds. Match on id (case-insensitive on
    # the alpha range) — `char` is typically unset for ctrl chords
    # outside the kitty-keyboard-protocol composed path.
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
                    $!change-supplier.emit($!buffer);
                    self.mark-dirty;
                }
                return True;
            }
        }
    }

    # Let other modified keys (except shift) bubble up for global
    # keybinds — *unless* the OS keyboard layout already composed the
    # modifier into a different printable character (e.g. UK Mac Alt-3
    # → '#', US Mac Alt-2 → '™'). When eff_text differs from the
    # keysym, the modifier was a composition input rather than a chord
    # intent, and blocking it makes those characters untypeable.
    my $composed = $ev.char.defined && $ev.char.chars == 1
                && $ev.char.ord >= 32 && $ev.char.ord != $ev.id;
    if !$composed && ($ev.has-modifier(Mod-Ctrl) || $ev.has-modifier(Mod-Alt) || $ev.has-modifier(Mod-Super)) {
        return self!check-keybinds($ev);
    }

    given $ev.id {
        when NCKEY_ENTER {
            $!submit-supplier.emit($!buffer);
            return True;
        }
        when NCKEY_BACKSPACE {
            if self.has-selection {
                self!delete-selection;
                $!change-supplier.emit($!buffer);
                self.mark-dirty;
            } elsif $shift {
                # Delete from cursor back to the previous word boundary.
                my $start = prev-word-pos($!buffer, $!cursor.Int);
                if $start < $!cursor {
                    $!buffer = $!buffer.substr(0, $start) ~ $!buffer.substr($!cursor);
                    $!cursor = $start.UInt;
                    $!change-supplier.emit($!buffer);
                    self.mark-dirty;
                }
            } elsif $!cursor > 0 {
                $!buffer = $!buffer.substr(0, $!cursor - 1) ~ $!buffer.substr($!cursor);
                $!cursor--;
                $!change-supplier.emit($!buffer);
                self.mark-dirty;
            }
            return True;
        }
        when NCKEY_DEL {
            if self.has-selection {
                self!delete-selection;
                $!change-supplier.emit($!buffer);
                self.mark-dirty;
            } elsif $!cursor < $!buffer.chars {
                $!buffer = $!buffer.substr(0, $!cursor) ~ $!buffer.substr($!cursor + 1);
                $!change-supplier.emit($!buffer);
                self.mark-dirty;
            }
            return True;
        }
        when NCKEY_LEFT {
            # Shift+Left preserves the existing word-jump shortcut and
            # additionally extends the selection — so the legacy
            # behaviour ("jump to prev word") and the new behaviour
            # ("extend selection by a word") share one bind, matching
            # the standard text-editor convention.
            if $shift {
                my $new = prev-word-pos($!buffer, $!cursor.Int);
                self!move-cursor($new.UInt, True) if $new != $!cursor;
            } elsif $!cursor > 0 {
                self!move-cursor($!cursor - 1, False);
            } else {
                self.clear-selection;
            }
            return True;
        }
        when NCKEY_RIGHT {
            if $shift {
                my $new = next-word-pos($!buffer, $!cursor.Int);
                self!move-cursor($new.UInt, True) if $new != $!cursor;
            } elsif $!cursor < $!buffer.chars {
                self!move-cursor($!cursor + 1, False);
            } else {
                self.clear-selection;
            }
            return True;
        }
        when NCKEY_HOME {
            self!move-cursor(0, $shift);
            return True;
        }
        when NCKEY_END {
            self!move-cursor($!buffer.chars, $shift);
            return True;
        }
        default {
            # Check registered keybinds (e.g. up/down for external navigation)
            return True if self!check-keybinds($ev);
            if $ev.char.defined && $ev.char.chars == 1 && $ev.char.ord >= 32 {
                self!delete-selection;   # type-replaces-selection
                $!buffer = $!buffer.substr(0, $!cursor) ~ $ev.char ~ $!buffer.substr($!cursor);
                $!cursor++;
                $!change-supplier.emit($!buffer);
                self.mark-dirty;
                return True;
            }
        }
    }
    False;
}
