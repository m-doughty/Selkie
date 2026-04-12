unit class Selkie::Event;

use Notcurses::Native::Types;
use Notcurses::Native::Input;

enum EventType is export (
    KeyEvent    => 'key',
    MouseEvent  => 'mouse',
    ResizeEvent => 'resize',
);

enum Modifier is export (
    Mod-Shift => 'shift',
    Mod-Alt   => 'alt',
    Mod-Ctrl  => 'ctrl',
    Mod-Super => 'super',
    Mod-Hyper => 'hyper',
    Mod-Meta  => 'meta',
);

has UInt $.id;
has Str $.char;
has Set $.modifiers;
has NcInputType $.input-type;
has EventType $.event-type;
has Int $.y = -1;
has Int $.x = -1;

method has-modifier(Modifier $mod --> Bool) {
    $mod ∈ $!modifiers;
}

method has-any-modifier(--> Bool) {
    ?$!modifiers;
}

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

class Keybind is export {
    has UInt $.id;
    has Str $.char;
    has Set $.modifiers;
    has &.handler is required;

    method parse(Str:D $spec, &handler --> Keybind) {
        my @parts = $spec.split('+');
        my @mods;
        my $key = @parts.pop;

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

        Keybind.new(:$id, :$char, modifiers => @mods.Set, :&handler);
    }

    method matches(Selkie::Event $ev --> Bool) {
        # Case-insensitive match for letter keys
        if $!id >= 'a'.ord && $!id <= 'z'.ord {
            # For letter keybinds, ignore Shift in modifier comparison
            # (user may press 'A' or 'a' — both should match keybind 'a')
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
