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

Two Supplies:

=item C<on-submit> — fires once when the user presses Enter, carrying the current text
=item C<on-change> — fires on every keystroke that modifies the buffer

For programmatic updates that shouldn't re-dispatch (e.g. syncing from
a store subscription), use C<set-text-silent> — it updates the buffer
without emitting on C<on-change>.

Modified keys (Ctrl, Alt, Super) bubble past the input so global
keybinds still work — except when the OS keyboard layout has already
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
has Str $.placeholder is rw = '';
has Str $.mask-char;
has Supplier $!submit-supplier = Supplier.new;
has Supplier $!change-supplier = Supplier.new;
has Bool $!focused = False;

method new(*%args --> Selkie::Widget::TextInput) {
    %args<focusable> //= True;
    callwith(|%args);
}

method text(--> Str) { $!buffer }

method set-text(Str:D $t) {
    $!buffer = $t;
    $!cursor = $t.chars;
    $!change-supplier.emit($!buffer);
    self.mark-dirty;
}

method set-text-silent(Str:D $t) {
    $!buffer = $t;
    $!cursor = $t.chars;
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

        # Draw cursor
        if $!focused {
            my UInt $cx = $!cursor - $!scroll-x;
            my $under = $!cursor < $display-buf.chars
                ?? $display-buf.substr($!cursor, 1) !! ' ';
            # Invert colors for cursor
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
    insert text. )
method insert-text(Str:D $text --> Nil) {
    my $clean = $text.subst(/\n/, '', :g).subst(/<[\x[00]..\x[1F]\x[7F]]>/, '', :g);
    return if $clean.chars == 0;
    $!buffer = $!buffer.substr(0, $!cursor) ~ $clean ~ $!buffer.substr($!cursor);
    $!cursor += $clean.chars;
    $!change-supplier.emit($!buffer);
    self.mark-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $!focused;
    return False unless $ev.input-type == NCTYPE_PRESS || $ev.input-type == NCTYPE_REPEAT
                     || $ev.input-type == NCTYPE_UNKNOWN;

    # Let modified keys (except shift) bubble up for global keybinds —
    # *unless* the OS keyboard layout already composed the modifier into
    # a different printable character (e.g. UK Mac Alt-3 → '#', US Mac
    # Alt-2 → '™'). When eff_text differs from the keysym, the modifier
    # was a composition input rather than a chord intent, and blocking
    # it makes those characters untypeable.
    my $composed = $ev.char.defined && $ev.char.chars == 1
                && $ev.char.ord >= 32 && $ev.char.ord != $ev.id;
    if !$composed && ($ev.has-modifier(Mod-Ctrl) || $ev.has-modifier(Mod-Alt) || $ev.has-modifier(Mod-Super)) {
        return self!check-keybinds($ev);
    }

    my $shift = $ev.has-modifier(Mod-Shift);

    given $ev.id {
        when NCKEY_ENTER {
            $!submit-supplier.emit($!buffer);
            return True;
        }
        when NCKEY_BACKSPACE {
            if $shift {
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
            if $!cursor < $!buffer.chars {
                $!buffer = $!buffer.substr(0, $!cursor) ~ $!buffer.substr($!cursor + 1);
                $!change-supplier.emit($!buffer);
                self.mark-dirty;
            }
            return True;
        }
        when NCKEY_LEFT {
            if $shift {
                my $new = prev-word-pos($!buffer, $!cursor.Int);
                if $new != $!cursor {
                    $!cursor = $new.UInt;
                    self.mark-dirty;
                }
            } elsif $!cursor > 0 {
                $!cursor--;
                self.mark-dirty;
            }
            return True;
        }
        when NCKEY_RIGHT {
            if $shift {
                my $new = next-word-pos($!buffer, $!cursor.Int);
                if $new != $!cursor {
                    $!cursor = $new.UInt;
                    self.mark-dirty;
                }
            } elsif $!cursor < $!buffer.chars {
                $!cursor++;
                self.mark-dirty;
            }
            return True;
        }
        when NCKEY_HOME {
            $!cursor = 0; self.mark-dirty;
            return True;
        }
        when NCKEY_END {
            $!cursor = $!buffer.chars; self.mark-dirty;
            return True;
        }
        default {
            # Check registered keybinds (e.g. up/down for external navigation)
            return True if self!check-keybinds($ev);
            if $ev.char.defined && $ev.char.chars == 1 && $ev.char.ord >= 32 {
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
