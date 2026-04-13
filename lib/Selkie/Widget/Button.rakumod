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
C<Space> while focused. Highlights visually while focused.

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

#| The text shown on the button. Required and immutable.
has Str $.label is required;

has Bool $!focused = False;
has Supplier $!press-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Button) {
    %args<focusable> //= True;
    callwith(|%args);
}

#| Supply that emits each time the user activates the button (Enter or
#| Space while focused).
method on-press(--> Supply) { $!press-supplier.Supply }

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
    return False unless $!focused;

    if $ev.event-type ~~ KeyEvent {
        if $ev.id == NCKEY_ENTER || $ev.id == NCKEY_SPACE {
            $!press-supplier.emit(True);
            return True;
        }
    }

    self!check-keybinds($ev);
}
