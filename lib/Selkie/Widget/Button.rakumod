=begin pod

=head1 NAME

Selkie::Widget::Button - Focusable clickable button

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Button;
use Selkie::Sizing;

my $ok = Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.fixed(1));
$ok.on-press.tap: -> $ { $app.store.dispatch('form/save') };

=end code

=head1 DESCRIPTION

Emits on its C<on-press> Supply when the user presses C<Enter> or
C<Space> while focused, or when they primary-click anywhere on the
button. Highlights visually while focused. The click path also takes
focus first (via L<Selkie::App>'s click-to-focus), so a mouse-driven
press leaves the button in the same state a keyboard press would.

Focusable by default (no need to pass C<focusable => True>). The label
is immutable after construction — build a new button if you need
different text.

=head1 EXAMPLES

=head2 A button row

=begin code :lang<raku>

my $row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $save = Selkie::Widget::Button.new(label => 'Save',   sizing => Sizing.flex);
my $undo = Selkie::Widget::Button.new(label => 'Undo',   sizing => Sizing.flex);
$row.add($save);
$row.add($undo);

$save.on-press.tap: -> $ { $app.store.dispatch('doc/save') };
$undo.on-press.tap: -> $ { $app.store.dispatch('doc/undo') };

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Checkbox> — focusable boolean toggle
=item L<Selkie::Widget::ConfirmModal> — pre-built yes/no dialog using Buttons

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::Button does Selkie::Widget;

#| The text shown on the button. Required at construction; use
#| C<set-label> to change afterwards (e.g. for counters).
has Str $.label is required;

has Bool $!focused = False;
has Supplier $!press-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Button) {
    %args<focusable> //= True;
    callwith(|%args);
}

submethod TWEAK() {
    # Mouse press fires the same activate path as Enter / Space. App's
    # dispatcher has already given us focus by the time this fires
    # (click-to-focus runs on PRESS before delivery), so the supply
    # emit matches the keyboard activation contract exactly.
    self.on-click: -> $ { $!press-supplier.emit(True) };
}

#| Supply that emits each time the user activates the button (Enter or
#| Space while focused).
method on-press(--> Supply) { $!press-supplier.Supply }

#| Replace the displayed label. Marks the widget dirty.
method set-label(Str:D $l) {
    $!label = $l;
    self.mark-dirty;
}

#| Called by C<Selkie::App.focus>. You don't usually call this yourself.
method set-focused(Bool $f) {
    $!focused = $f;
    self.mark-dirty;
}

#| True if the button currently has focus.
method is-focused(--> Bool) { $!focused }

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $w = self.cols;

    if $!focused {
        # Highlighted: bright text on contrasting bg with brackets
        ncplane_set_fg_rgb(self.plane, 0xFFFFFF);
        ncplane_set_bg_rgb(self.plane, 0x4A4A8A);
        ncplane_set_styles(self.plane, NCSTYLE_BOLD);
        my $display = "[ {$!label} ]";
        my $pad = ($w - $display.chars) max 0;
        my $left = $pad div 2;
        my $text = (' ' x $left) ~ $display ~ (' ' x ($pad - $left));
        ncplane_putstr_yx(self.plane, 0, 0, $text.substr(0, $w));
    } else {
        # Normal: dim
        my $style = self.theme.input;
        self.apply-style($style);
        my $display = "  {$!label}  ";
        my $pad = ($w - $display.chars) max 0;
        my $left = $pad div 2;
        my $text = (' ' x $left) ~ $display ~ (' ' x ($pad - $left));
        ncplane_putstr_yx(self.plane, 0, 0, $text.substr(0, $w));
    }

    self.clear-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    # Mouse events route through the registration API regardless of
    # focus state — App's coordinate-based dispatch only reaches us
    # if a click landed in our rect, and click-to-focus has already
    # promoted us to the focused widget on press.
    if $ev.event-type ~~ MouseEvent {
        return True if self!dispatch-mouse-handlers($ev);
        return False;
    }

    return False unless $!focused;

    if $ev.event-type ~~ KeyEvent {
        if $ev.id == NCKEY_ENTER || $ev.id == NCKEY_SPACE {
            $!press-supplier.emit(True);
            return True;
        }
        # Left / Right cycle focus the same way Tab / Shift-Tab do.
        # Buttons in a modal's action row sit horizontally — most
        # users reach for the arrow keys before they reach for Tab,
        # and stranding focus on a single button until they discover
        # Tab is bad UX. Dispatch the same store events App's
        # global Tab keybinds use, so the focus chain semantics
        # stay identical (focusable-descendants order, modal focus
        # traps, etc.).
        if $ev.id == NCKEY_LEFT && !$ev.modifiers.elems {
            self.dispatch('ui/focus-prev');
            return True;
        }
        if $ev.id == NCKEY_RIGHT && !$ev.modifiers.elems {
            self.dispatch('ui/focus-next');
            return True;
        }
    }

    self!check-keybinds($ev);
}
