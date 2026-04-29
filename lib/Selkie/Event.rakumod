=begin pod

=head1 NAME

Selkie::Event - Keyboard, mouse, and resize event abstraction

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Event;
use Notcurses::Native::Types;

# In a widget's handle-event method:
method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $ev.event-type ~~ KeyEvent;

    given $ev.id {
        when NCKEY_UP    { self!cursor-up;   return True }
        when NCKEY_DOWN  { self!cursor-down; return True }
        when NCKEY_ENTER { self!activate;    return True }
    }

    # Printable character?
    if $ev.char.defined && $ev.char.chars == 1 && $ev.char.ord >= 32 {
        self!insert-char($ev.char);
        return True;
    }

    False;   # not consumed — bubble to parent
}

=end code

=head1 DESCRIPTION

Every input event — keystrokes, mouse clicks, terminal resizes — is
wrapped in a C<Selkie::Event> before reaching widgets. The event carries:

=item An C<id> — the keycode (C<NCKEY_*>) or character codepoint
=item A C<char> — the effective printable character, if any (handles Shift correctly: Shift+1 → C<'!'>)
=item The C<modifiers> that were held — a C<Set> of C<Modifier> values
=item The C<input-type> — PRESS, RELEASE, REPEAT (see C<NcInputType>)
=item The C<event-type> — C<KeyEvent>, C<MouseEvent>, or C<ResizeEvent>
=item Mouse coordinates (C<x>, C<y>) for mouse events

Widgets implement C<handle-event(Selkie::Event)> returning Bool. True
means the event was consumed; False lets it bubble to the parent chain
and eventually to the app's global keybinds.

This module also exports L<Keybind> — the parsed form used by
C<on-key> on widgets and C<Selkie::App>.

=head1 EXAMPLES

=head2 Character input

When the user types a printable character on a focused widget, you get
it in C<$ev.char>:

=begin code :lang<raku>

if $ev.char.defined && $ev.char.chars == 1 && $ev.char.ord >= 32 {
    # Printable — insert into buffer
    $!buffer ~= $ev.char;
    $!change-supplier.emit($!buffer);
    return True;
}

=end code

Note the C<.ord >= 32> guard: that filters out control characters (which
arrive with C<id> in the 1–26 range) so Ctrl+X combos aren't mistaken
for typed input.

=head2 Checking modifiers

Use C<has-modifier> to test for a specific modifier key:

=begin code :lang<raku>

if $ev.id == NCKEY_ENTER && $ev.has-modifier(Mod-Ctrl) {
    self!submit;        # Ctrl+Enter submits
    return True;
} elsif $ev.id == NCKEY_ENTER {
    self!insert-newline;   # plain Enter inserts a newline
    return True;
}

=end code

=head2 Mouse events

For mouse events, C<id> is one of the C<NCKEY_SCROLL_UP>, C<NCKEY_BUTTON1>,
etc. constants, and C<x>/C<y> give the click coordinates:

=begin code :lang<raku>

if $ev.event-type ~~ MouseEvent {
    given $ev.id {
        when NCKEY_SCROLL_UP   { self!scroll(-1); return True }
        when NCKEY_SCROLL_DOWN { self!scroll(1);  return True }
    }
}

=end code

=head1 KEYBIND SYNTAX

C<Keybind.parse> and the C<on-key> methods accept a string spec:

=item Single character: C<'a'>, C<'?'>, C<'Q'>, C<'+'>
=item Named keys: C<'enter'>, C<'tab'>, C<'esc'> (or C<'escape'>), C<'space'>, C<'backspace'>, C<'delete'>, C<'insert'>, C<'home'>, C<'end'>, C<'pgup'>, C<'pgdown'>, C<'up'>, C<'down'>, C<'left'>, C<'right'>
=item Function keys: C<'f1'> through C<'f60'>
=item Modifiers: C<'ctrl+'>, C<'alt+'>, C<'shift+'>, C<'super+'>, C<'hyper+'>, C<'meta+'> — combinable, e.g. C<'ctrl+shift+a'>

Letter keybinds are case-insensitive — C<'a'> matches both C<a> and C<A>
(with Shift held).

The literal C<'+'> key is bindable too: write it as C<'+'> on its own,
or as C<'shift++'>, C<'ctrl++'>, C<'ctrl+shift++'>, etc. The parser
recognises a trailing C<'+'> as the key when the rest of the spec
already supplies one or more modifiers.

=head1 SEE ALSO

=item L<Selkie::Widget> — widgets receive events via C<handle-event>
=item L<Selkie::App> — the event loop dispatches to focused widget first, then parent chain, then global keybinds

=end pod

unit class Selkie::Event;

use Notcurses::Native::Types;
use Notcurses::Native::Input;

#| Category of event. C<KeyEvent> for keystrokes, C<MouseEvent> for clicks
#| and scrolls, C<ResizeEvent> for terminal resizes.
enum EventType is export (
    KeyEvent    => 'key',
    MouseEvent  => 'mouse',
    ResizeEvent => 'resize',
);

#| Modifier keys. Test with C<$ev.has-modifier(Mod-Ctrl)>, etc.
enum Modifier is export (
    Mod-Shift => 'shift',
    Mod-Alt   => 'alt',
    Mod-Ctrl  => 'ctrl',
    Mod-Super => 'super',
    Mod-Hyper => 'hyper',
    Mod-Meta  => 'meta',
);

#| The keycode or character codepoint of the event. For named keys this
#| is an C<NCKEY_*> constant; for printable characters it's the ordinal.
has UInt $.id;

#| The effective printable character, if any. Respects Shift (Shift+1 →
#| C<'!'>). Undefined for non-printable keys, synthesised events, and
#| legacy control sequences.
has Str $.char;

#| The set of modifier keys held when the event fired. Test with C<has-modifier>.
has Set $.modifiers;

#| The input type: NCTYPE_PRESS, NCTYPE_RELEASE, NCTYPE_REPEAT, etc.
#| The framework typically filters RELEASE events before dispatching.
has NcInputType $.input-type;

#| Which category this event belongs to — see L<EventType>.
has EventType $.event-type;

#| Mouse Y coordinate for C<MouseEvent>, -1 otherwise.
has Int $.y = -1;

#| Mouse X coordinate for C<MouseEvent>, -1 otherwise.
has Int $.x = -1;

#| True if the given modifier is part of the event's modifier set.
method has-modifier(Modifier $mod --> Bool) {
    $mod ∈ $!modifiers;
}

#| True if any modifier is held. Useful for "pass bare keys to the
#| widget, bubble modified keys to global keybinds" branches.
method has-any-modifier(--> Bool) {
    ?$!modifiers;
}

#|( Build a C<Selkie::Event> from a raw notcurses C<Ncinput> struct.
    Called by C<Selkie::App> inside the event loop — you don't normally
    call this yourself. Handles: resize detection, mouse vs key
    classification, modifier bit decoding, effective character resolution
    for Shift + key combos, and legacy Ctrl+A..Z control-code remapping
    for terminals without the kitty keyboard protocol. )
method from-ncinput(Ncinput $ni --> Selkie::Event) {
    my $id = $ni.id;

    my $event-type = do given $id {
        when NCKEY_RESIZE { ResizeEvent }
        when { nckey_mouse_p($id) } { MouseEvent }
        default { KeyEvent }
    };

    my @mods;
    my $mod-bits = $ni.modifiers;
    @mods.push(Mod-Shift) if $mod-bits +& NCKEY_MOD_SHIFT;
    @mods.push(Mod-Alt)   if $mod-bits +& NCKEY_MOD_ALT;
    @mods.push(Mod-Ctrl)  if $mod-bits +& NCKEY_MOD_CTRL;
    @mods.push(Mod-Super) if $mod-bits +& NCKEY_MOD_SUPER;
    @mods.push(Mod-Hyper) if $mod-bits +& NCKEY_MOD_HYPER;
    @mods.push(Mod-Meta)  if $mod-bits +& NCKEY_MOD_META;

    my $char = Str;
    my $resolved-id = $id;

    # Detect legacy ctrl sequences: control codes 1-26 map to Ctrl+A through Ctrl+Z
    # Terminals without kitty keyboard protocol send these instead of modifier flags
    # Exclude real keys that happen to be in this range: Tab(9), Enter(13)
    my constant %ctrl-exceptions = 9 => True, 10 => True, 13 => True;
    if $id >= 1 && $id <= 26 && Mod-Ctrl ∉ @mods && !%ctrl-exceptions{$id} {
        @mods.push(Mod-Ctrl);
        $resolved-id = $id + 96;  # map to lowercase letter (1 → 'a', 17 → 'q')
        $char = $resolved-id.chr;
    } elsif !nckey_synthesized_p($id) {
        # Use eff_text (effective text) for the actual character produced
        # This handles Shift+key correctly (e.g., Shift+1 → '!')
        my $eff = $ni.eff_text_0;
        if $eff > 0 && $eff < 0x110000 {
            $char = $eff.chr;
        } elsif $id > 0 && $id < 0x110000 {
            $char = $id.chr;
        }
    }

    Selkie::Event.new(
        id         => $resolved-id,
        :$char,
        modifiers  => @mods.Set,
        input-type => NcInputType($ni.evtype),
        :$event-type,
        y          => $ni.y,
        x          => $ni.x,
    );
}

=begin pod

=head1 Keybind

A parsed keybind specification, produced by C<Keybind.parse> and matched
against events via C<matches>. You don't normally construct or match
these yourself — C<on-key> does it for you — but the class is exposed
so advanced code can inspect registered binds.

=end pod

class Keybind is export {
    #| The target keycode / character codepoint.
    has UInt $.id;

    #| The target character, if the bind was for a single character.
    has Str $.char;

    #| The modifier set that must be held for a match.
    has Set $.modifiers;

    #| The original spec string the bind was parsed from. Useful for
    #| help-overlay rendering ("Ctrl+L  — Lorebooks").
    has Str $.spec;

    #| Optional human-readable description of what the bind does. Set
    #| via the C<:description> arg on C<Widget.on-key>; surfaced by
    #| L<Selkie::Widget::HelpOverlay>.
    has Str $.description = '';

    #| The handler callable invoked on match.
    has &.handler is required;

    #|( Parse a keybind spec string into a C<Keybind>. Spec grammar is
        described under L<KEYBIND SYNTAX> in this module's main pod.
        Throws on unknown modifiers or unknown key names. )
    method parse(Str:D $spec, &handler, Str :$description = '' --> Keybind) {
        my @parts;
        my Str $key;

        # `+` is the modifier separator, so a naive split would leave the
        # key half empty whenever the key itself is `+`. Detect those
        # forms — `'+'`, `'shift++'`, `'ctrl+shift++'`, etc. — first and
        # peel the trailing `+` off as the literal key. Specs that end
        # with a single trailing `+` and nothing after (e.g. `'shift+'`)
        # are still treated as malformed and fail in the key parser
        # below, preserving the prior "no empty key" invariant.
        if $spec eq '+' {
            @parts = ();
            $key = '+';
        } elsif $spec.chars >= 2 && $spec.ends-with('++') {
            @parts = $spec.substr(0, *-2).split('+');
            $key = '+';
        } else {
            @parts = $spec.split('+');
            $key = @parts.pop;
        }

        my @mods;

        for @parts -> $mod {
            @mods.push: do given $mod.lc {
                when 'ctrl'  { Mod-Ctrl  }
                when 'alt'   { Mod-Alt   }
                when 'shift' { Mod-Shift }
                when 'super' { Mod-Super }
                when 'hyper' { Mod-Hyper }
                when 'meta'  { Mod-Meta  }
                default { die "Unknown modifier: $mod" }
            };
        }

        my UInt $id;
        my Str $char;

        given $key.lc {
            when 'enter'     { $id = NCKEY_ENTER     }
            when 'tab'       { $id = NCKEY_TAB       }
            when 'esc'       { $id = NCKEY_ESC       }
            when 'escape'    { $id = NCKEY_ESC       }
            when 'space'     { $id = NCKEY_SPACE     }
            when 'backspace' { $id = NCKEY_BACKSPACE }
            when 'delete'    { $id = NCKEY_DEL       }
            when 'insert'    { $id = NCKEY_INS       }
            when 'home'      { $id = NCKEY_HOME      }
            when 'end'       { $id = NCKEY_END       }
            when 'pgup'      { $id = NCKEY_PGUP      }
            when 'pgdown'    { $id = NCKEY_PGDOWN    }
            when 'up'        { $id = NCKEY_UP        }
            when 'down'      { $id = NCKEY_DOWN      }
            when 'left'      { $id = NCKEY_LEFT      }
            when 'right'     { $id = NCKEY_RIGHT     }
            when /^ 'f' (\d+) $/ {
                my $n = +$0;
                die "Invalid function key: f$n" unless 0 <= $n <= 60;
                $id = NCKEY_F00 + $n;
            }
            when .chars == 1 {
                $char = $key;
                $id = $key.ord;
            }
            default { die "Unknown key: $key" }
        }

        Keybind.new(:$id, :$char, modifiers => @mods.Set, :&handler, :$spec, :$description);
    }

    #|( Does the given event match this keybind? Letter binds are
        case-insensitive — C<'a'> matches a typed C<A> with Shift held.
        All other binds require an exact modifier-set match. )
    method matches(Selkie::Event $ev --> Bool) {
        if $!id >= 'a'.ord && $!id <= 'z'.ord {
            my $ev-mods = $ev.modifiers (-) Set(Mod-Shift);
            my $kb-mods = $!modifiers (-) Set(Mod-Shift);
            return False unless $ev-mods eqv $kb-mods;
            my $ev-lower = $ev.id >= 'A'.ord && $ev.id <= 'Z'.ord
                           ?? $ev.id + 32
                           !! $ev.id;
            return $ev-lower == $!id;
        }
        return False unless $ev.modifiers eqv $!modifiers;
        $ev.id == $!id;
    }
}
