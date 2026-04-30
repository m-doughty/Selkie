=begin pod

=head1 NAME

Selkie::Widget::Checkbox - Focusable boolean toggle

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Checkbox;
use Selkie::Sizing;

my $cb = Selkie::Widget::Checkbox.new(
    label  => 'Enable notifications',
    sizing => Sizing.fixed(1),
);
$cb.on-change.tap: -> Bool $checked {
    $app.store.dispatch('settings/notifications', value => $checked);
};

=end code

=head1 DESCRIPTION

Renders as C<[x] label> when checked, C<[ ] label> when unchecked.
Space or Enter toggles the state, as does a primary mouse click on
any cell of the checkbox row.

C<set-checked> is idempotent — passing the current value is a no-op and
doesn't emit on C<on-change>. Safe to call from a store subscription
without causing feedback loops.

=head1 EXAMPLES

=head2 Syncing with the store

=begin code :lang<raku>

# Subscribe: reflect store changes into the widget
$app.store.subscribe-with-callback(
    'sync-notif',
    -> $s { $s.get-in('settings', 'notifications') // True },
    -> Bool $v { $cb.set-checked($v) },   # no-op if unchanged — safe
    $cb,
);

# Emit: user toggle dispatches to the store
$cb.on-change.tap: -> Bool $v {
    $app.store.dispatch('settings/set', field => 'notifications', value => $v);
};

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::RadioGroup> — one-of-many selection
=item L<Selkie::Widget::Button> — plain action button

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::Checkbox does Selkie::Widget;

#| The label displayed after the C<[x]> / C<[ ]> indicator. Required.
has Str $.label is required;

has Bool $!checked = False;
has Bool $!focused = False;
has Supplier $!change-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Checkbox) {
    %args<focusable> //= True;
    callwith(|%args);
}

submethod TWEAK() {
    # Primary mouse click toggles, same path as Enter / Space.
    self.on-click: -> $ { self.toggle };
}

#| Current state.
method checked(--> Bool) { $!checked }

#|( Set the state, emitting on-change only if the value actually
    changed. No-op on same-value assignments — safe to call from a
    store subscription. )
method set-checked(Bool:D $v) {
    return if $v == $!checked;
    $!checked = $v;
    $!change-supplier.emit($!checked);
    self.mark-dirty;
}

#| Flip the state and emit on-change unconditionally.
method toggle() {
    $!checked = !$!checked;
    $!change-supplier.emit($!checked);
    self.mark-dirty;
}

#| Supply emitting C<Bool> each time the state changes.
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
    if $ev.event-type ~~ MouseEvent {
        return True if self!dispatch-mouse-handlers($ev);
        return False;
    }

    return False unless $!focused;

    if $ev.event-type ~~ KeyEvent {
        if $ev.id == NCKEY_ENTER || $ev.id == NCKEY_SPACE {
            self.toggle;
            return True;
        }
    }

    self!check-keybinds($ev);
}
