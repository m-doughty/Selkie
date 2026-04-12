use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::Button does Selkie::Widget;

has Str $.label is required;
has Bool $!focused = False;
has Supplier $!press-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Button) {
    %args<focusable> //= True;
    callwith(|%args);
}

method on-press(--> Supply) { $!press-supplier.Supply }

method set-focused(Bool $f) {
    $!focused = $f;
    self.mark-dirty;
}

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
