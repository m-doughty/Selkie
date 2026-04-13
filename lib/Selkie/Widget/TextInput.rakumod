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
keybinds still work. Bare characters are consumed for typing.

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

method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $!focused;
    return False unless $ev.input-type == NCTYPE_PRESS || $ev.input-type == NCTYPE_REPEAT
                     || $ev.input-type == NCTYPE_UNKNOWN;

    # Let modified keys (except shift) bubble up for global keybinds
    if $ev.has-modifier(Mod-Ctrl) || $ev.has-modifier(Mod-Alt) || $ev.has-modifier(Mod-Super) {
        return self!check-keybinds($ev);
    }

    given $ev.id {
        when NCKEY_ENTER {
            $!submit-supplier.emit($!buffer);
            return True;
        }
        when NCKEY_BACKSPACE {
            if $!cursor > 0 {
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
            if $!cursor > 0 { $!cursor--; self.mark-dirty }
            return True;
        }
        when NCKEY_RIGHT {
            if $!cursor < $!buffer.chars { $!cursor++; self.mark-dirty }
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
