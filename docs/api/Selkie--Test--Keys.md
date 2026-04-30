NAME
====

Selkie::Test::Keys - Keystroke synthesis helpers for widget tests

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

Every widget test currently declares its own `sub key-event` that takes `:id`, `:char`, `:modifiers`, etc. and builds a [Selkie::Event](Selkie--Event.md). This module provides a shared, higher-level alternative: parse a string spec (the same grammar used by `on-key`) and produce the equivalent event.

Three levels of convenience:

  * `press-key($widget, $spec)` — build an event from the spec, dispatch it to `$widget.handle-event`, return whether it was consumed. The workhorse for assertions like "pressing Enter activates the button".

  * `key-event($spec)` — just build the event, don't dispatch. Useful when you want to inspect it or dispatch to multiple widgets.

  * `mouse-event(...)`, `resize-event()` — constructors for the non-keyboard event types.

The string spec accepts everything [Selkie::Event](Selkie--Event.md)'s `Keybind.parse` accepts: `'a'`, `'ctrl+q'`, `'enter'`, `'shift+tab'`, `'f1'`, etc. See [Selkie::Event](Selkie--Event.md) for the full grammar.

EXAMPLES
========

A typical widget test
---------------------

```raku
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
```

Modifier keys
-------------

```raku
press-key($widget, 'ctrl+c');          # Ctrl+C
press-key($widget, 'alt+shift+f');     # Alt+Shift+F
press-key($widget, 'super+space');     # Super+Space
```

Mouse events
------------

```raku
my $ev = mouse-event(id => NCKEY_SCROLL_UP);
$widget.handle-event($ev);

my $click = mouse-event(id => NCKEY_BUTTON1, y => 5, x => 10);
$widget.handle-event($click);
```

SEE ALSO
========

  * [Selkie::Event](Selkie--Event.md) — the underlying event class and spec grammar

  * [Selkie::Widget](Selkie--Widget.md) — `handle-event` is what everything dispatches to

### multi sub key-event

```raku
multi sub key-event(
    Str:D $spec,
    NcInputType :$input-type = NcInputType::NCTYPE_PRESS
) returns Selkie::Event
```

Build a [Selkie::Event](Selkie--Event.md) from a keybind spec string. Accepts the same grammar as `on-key`: single chars (`'a'`), named keys (`'enter'`, `'tab'`, `'esc'`), function keys (`'f1'`..`'f60'`), and modifier combos (`'ctrl+shift+a'`). Defaults to a press event. Multi-dispatch — the low-level form takes explicit `:id` and `:char` for cases where you need an event that doesn't correspond to a spec (e.g. a synthesised resize).

### sub press-key

```raku
sub press-key(
    Selkie::Widget $widget,
    Str:D $spec,
    NcInputType :$input-type = NcInputType::NCTYPE_PRESS
) returns Bool
```

Build and dispatch a keystroke to a widget in one call. Returns `True` if the widget consumed the event, `False` otherwise — same contract as `handle-event`.

### sub press-keys

```raku
sub press-keys(
    Selkie::Widget $widget,
    *@specs
) returns Bool
```

Dispatch a sequence of keys to a widget. Returns True if any key was consumed. Equivalent to calling `press-key` for each spec in order. press-keys($list, 'down', 'down', 'enter');

### sub type-text

```raku
sub type-text(
    Selkie::Widget $widget,
    Str:D $text
) returns Mu
```

Type a string into a widget by dispatching one key event per character. Newlines (`\n`) are sent as `enter`. Useful for simulating user typing into TextInput / MultiLineInput: type-text($input, 'hello world'); type-text($multi-line, "line one\nline two");

### sub mouse-event

```raku
sub mouse-event(
    Int :$id! where { ... },
    Int :$y = Code.new,
    Int :$x = Code.new,
    Set :$modifiers = Code.new,
    NcInputType :$input-type = NcInputType::NCTYPE_PRESS,
    Int :$click-count = 0
) returns Selkie::Event
```

Construct a mouse event. `:id` is one of `NCKEY_SCROLL_UP`, `NCKEY_SCROLL_DOWN`, `NCKEY_BUTTON1..6`, or `NCKEY_MOTION`. `:y` and `:x` are optional screen coordinates. `:click-count` annotates a press with multiplicity (1 single, 2 double, 3 triple) — production code receives this from `Selkie::App`'s mouse dispatcher.

### sub resize-event

```raku
sub resize-event() returns Selkie::Event
```

Construct a terminal-resize event. The `id` on a real resize is `NCKEY_RESIZE` (the framework's event-type classifier recognises it); we replicate that here.

