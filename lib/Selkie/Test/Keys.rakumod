=begin pod

=head1 NAME

Selkie::Test::Keys - Keystroke synthesis helpers for widget tests

=head1 SYNOPSIS

=begin code :lang<raku>

use Test;
use Selkie::Test::Keys;
use Selkie::Widget::Button;

my $button = Selkie::Widget::Button.new(label => 'OK');
$button.set-focused(True);

my $pressed = False;
$button.on-press.tap: -> $ { $pressed = True };

# Build + dispatch a keystroke in one call
press-key($button, 'enter');
ok $pressed, 'Enter activated the button';

# Or just build an event for finer control
my $ev = key-event('ctrl+shift+a');
say $ev.modifiers;   # Set(Mod-Ctrl, Mod-Shift)

done-testing;

=end code

=head1 DESCRIPTION

Every widget test currently declares its own C<sub key-event> that takes
C<:id>, C<:char>, C<:modifiers>, etc. and builds a L<Selkie::Event>.
This module provides a shared, higher-level alternative: parse a string
spec (the same grammar used by C<on-key>) and produce the equivalent
event.

Three levels of convenience:

=item C<press-key($widget, $spec)> — build an event from the spec, dispatch it to C<$widget.handle-event>, return whether it was consumed. The workhorse for assertions like "pressing Enter activates the button".
=item C<key-event($spec)> — just build the event, don't dispatch. Useful when you want to inspect it or dispatch to multiple widgets.
=item C<mouse-event(...)>, C<resize-event()> — constructors for the non-keyboard event types.

The string spec accepts everything L<Selkie::Event>'s C<Keybind.parse>
accepts: C<'a'>, C<'ctrl+q'>, C<'enter'>, C<'shift+tab'>, C<'f1'>, etc.
See L<Selkie::Event> for the full grammar.

=head1 EXAMPLES

=head2 A typical widget test

=begin code :lang<raku>

use Test;
use Selkie::Test::Keys;
use Selkie::Widget::ListView;

my $list = Selkie::Widget::ListView.new;
$list.set-items(<alpha beta gamma>);

press-key($list, 'down');
is $list.cursor, 1, 'down moves cursor';

press-key($list, 'end');
is $list.cursor, 2, 'end jumps to last';

my $activated;
$list.on-activate.tap: -> $ v { $activated = $v };
press-key($list, 'enter');
is $activated, 'gamma', 'enter activates selected';

=end code

=head2 Modifier keys

=begin code :lang<raku>

press-key($widget, 'ctrl+c');          # Ctrl+C
press-key($widget, 'alt+shift+f');     # Alt+Shift+F
press-key($widget, 'super+space');     # Super+Space

=end code

=head2 Mouse events

=begin code :lang<raku>

my $ev = mouse-event(id => NCKEY_SCROLL_UP);
$widget.handle-event($ev);

my $click = mouse-event(id => NCKEY_BUTTON1, y => 5, x => 10);
$widget.handle-event($click);

=end code

=head1 SEE ALSO

=item L<Selkie::Event> — the underlying event class and spec grammar
=item L<Selkie::Widget> — C<handle-event> is what everything dispatches to

=end pod

unit module Selkie::Test::Keys;

use Notcurses::Native::Types;
use Selkie::Event;
use Selkie::Widget;

#|( Build a L<Selkie::Event> from a keybind spec string. Accepts the same
    grammar as C<on-key>: single chars (C<'a'>), named keys (C<'enter'>,
    C<'tab'>, C<'esc'>), function keys (C<'f1'>..C<'f60'>), and modifier
    combos (C<'ctrl+shift+a'>). Defaults to a press event.

    Multi-dispatch — the low-level form takes explicit C<:id> and C<:char>
    for cases where you need an event that doesn't correspond to a spec
    (e.g. a synthesised resize). )
multi sub key-event(Str:D $spec,
                    NcInputType :$input-type = NCTYPE_PRESS
                    --> Selkie::Event
) is export {
    my $kb = Keybind.parse($spec, -> $ { });
    Selkie::Event.new(
        id         => $kb.id,
        char       => $kb.char,
        modifiers  => $kb.modifiers,
        :$input-type,
        event-type => KeyEvent,
    );
}

multi sub key-event(UInt :$id!,
                    Str :$char,
                    Set :$modifiers = Set.new,
                    NcInputType :$input-type = NCTYPE_PRESS
                    --> Selkie::Event
) is export {
    Selkie::Event.new(
        :$id, :$char, :$modifiers, :$input-type,
        event-type => KeyEvent,
    );
}

#|( Build and dispatch a keystroke to a widget in one call. Returns
    C<True> if the widget consumed the event, C<False> otherwise — same
    contract as C<handle-event>. )
sub press-key(Selkie::Widget $widget, Str:D $spec,
              NcInputType :$input-type = NCTYPE_PRESS
              --> Bool
) is export {
    my $ev = key-event($spec, :$input-type);
    $widget.handle-event($ev);
}

#|( Dispatch a sequence of keys to a widget. Returns True if any key
    was consumed. Equivalent to calling C<press-key> for each spec in
    order.

        press-keys($list, 'down', 'down', 'enter');
)
sub press-keys(Selkie::Widget $widget, *@specs --> Bool) is export {
    my Bool $any = False;
    for @specs -> $spec {
        $any = press-key($widget, $spec) || $any;
    }
    $any;
}

#|( Type a string into a widget by dispatching one key event per
    character. Newlines (C<\n>) are sent as C<enter>. Useful for
    simulating user typing into TextInput / MultiLineInput:

        type-text($input, 'hello world');
        type-text($multi-line, "line one\nline two");
)
sub type-text(Selkie::Widget $widget, Str:D $text) is export {
    for $text.comb -> $char {
        if $char eq "\n" {
            press-key($widget, 'enter');
        } else {
            press-key($widget, $char);
        }
    }
}

#|( Construct a mouse event. C<:id> is one of C<NCKEY_SCROLL_UP>,
    C<NCKEY_SCROLL_DOWN>, C<NCKEY_BUTTON1..6>, or C<NCKEY_MOTION>.
    C<:y> and C<:x> are optional screen coordinates. C<:click-count>
    annotates a press with multiplicity (1 single, 2 double, 3
    triple) — production code receives this from C<Selkie::App>'s
    mouse dispatcher. )
sub mouse-event(UInt :$id!,
                Int :$y = -1,
                Int :$x = -1,
                Set :$modifiers = Set.new,
                NcInputType :$input-type = NCTYPE_PRESS,
                Int :$click-count = 0
                --> Selkie::Event
) is export {
    Selkie::Event.new(
        :$id, :$modifiers, :$input-type, :$y, :$x, :$click-count,
        event-type => MouseEvent,
    );
}

#|( Construct a terminal-resize event. The C<id> on a real resize is
    C<NCKEY_RESIZE> (the framework's event-type classifier recognises
    it); we replicate that here. )
sub resize-event(--> Selkie::Event) is export {
    Selkie::Event.new(
        id         => NCKEY_RESIZE,
        modifiers  => Set.new,
        input-type => NCTYPE_PRESS,
        event-type => ResizeEvent,
    );
}
