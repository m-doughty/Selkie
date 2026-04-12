use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::Checkbox does Selkie::Widget;

has Str $.label is required;
has Bool $!checked = False;
has Bool $!focused = False;
has Supplier $!change-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Checkbox) {
    %args<focusable> //= True;
    callwith(|%args);
}

method checked(--> Bool) { $!checked }

method set-checked(Bool:D $v) {
    return if $v == $!checked;
    $!checked = $v;
    $!change-supplier.emit($!checked);
    self.mark-dirty;
}

method toggle() {
    $!checked = !$!checked;
    $!change-supplier.emit($!checked);
    self.mark-dirty;
}

method on-change(--> Supply) { $!change-supplier.Supply }

method set-focused(Bool $f) {
    $!focused = $f;
    self.mark-dirty;
}

method is-focused(--> Bool) { $!focused }

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $w = self.cols;
    my $indicator = $!checked ?? '[x]' !! '[ ]';
    my $display = "$indicator $!label";
    $display = $display.substr(0, $w) if $display.chars > $w;

    if $!focused {
        ncplane_set_fg_rgb(self.plane, 0xFFFFFF);
        ncplane_set_bg_rgb(self.plane, 0x4A4A8A);
        ncplane_set_styles(self.plane, NCSTYLE_BOLD);
    } else {
        my $style = self.theme.text;
        self.apply-style($style);
    }

    # Pad to full width for consistent background
    my $padded = $display ~ (' ' x (($w - $display.chars) max 0));
    ncplane_putstr_yx(self.plane, 0, 0, $padded.substr(0, $w));

    self.clear-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $!focused;

    if $ev.event-type ~~ KeyEvent {
        if $ev.id == NCKEY_ENTER || $ev.id == NCKEY_SPACE {
            self.toggle;
            return True;
        }
    }

    self!check-keybinds($ev);
}
