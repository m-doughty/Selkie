NAME
====

Selkie::Event - Keyboard, mouse, and resize event abstraction

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

Every input event — keystrokes, mouse clicks, terminal resizes — is wrapped in a `Selkie::Event` before reaching widgets. The event carries:

  * An `id` — the keycode (`NCKEY_*`) or character codepoint

  * A `char` — the effective printable character, if any (handles Shift correctly: Shift+1 → `'!'`)

  * The `modifiers` that were held — a `Set` of `Modifier` values

  * The `input-type` — PRESS, RELEASE, REPEAT (see `NcInputType`)

  * The `event-type` — `KeyEvent`, `MouseEvent`, or `ResizeEvent`

  * Mouse coordinates (`x`, `y`) for mouse events

Widgets implement `handle-event(Selkie::Event)` returning Bool. True means the event was consumed; False lets it bubble to the parent chain and eventually to the app's global keybinds.

This module also exports [Keybind](Keybind) — the parsed form used by `on-key` on widgets and `Selkie::App`.

EXAMPLES
========

Character input
---------------

When the user types a printable character on a focused widget, you get it in `$ev.char`:

```raku
if $ev.char.defined && $ev.char.chars == 1 && $ev.char.ord >= 32 {
    # Printable — insert into buffer
    $!buffer ~= $ev.char;
    $!change-supplier.emit($!buffer);
    return True;
}
```

Note the `.ord `= 32> guard: that filters out control characters (which arrive with `id` in the 1–26 range) so Ctrl+X combos aren't mistaken for typed input.

Checking modifiers
------------------

Use `has-modifier` to test for a specific modifier key:

```raku
if $ev.id == NCKEY_ENTER && $ev.has-modifier(Mod-Ctrl) {
    self!submit;        # Ctrl+Enter submits
    return True;
} elsif $ev.id == NCKEY_ENTER {
    self!insert-newline;   # plain Enter inserts a newline
    return True;
}
```

Mouse events
------------

For mouse events, `id` is one of the `NCKEY_SCROLL_UP`, `NCKEY_BUTTON1`, etc. constants, and `x`/`y` give the click coordinates:

```raku
if $ev.event-type ~~ MouseEvent {
    given $ev.id {
        when NCKEY_SCROLL_UP   { self!scroll(-1); return True }
        when NCKEY_SCROLL_DOWN { self!scroll(1);  return True }
    }
}
```

KEYBIND SYNTAX
==============

`Keybind.parse` and the `on-key` methods accept a string spec:

  * Single character: `'a'`, `'?'`, `'Q'`

  * Named keys: `'enter'`, `'tab'`, `'esc'` (or `'escape'`), `'space'`, `'backspace'`, `'delete'`, `'insert'`, `'home'`, `'end'`, `'pgup'`, `'pgdown'`, `'up'`, `'down'`, `'left'`, `'right'`

  * Function keys: `'f1'` through `'f60'`

  * Modifiers: `'ctrl+'`, `'alt+'`, `'shift+'`, `'super+'`, `'hyper+'`, `'meta+'` — combinable, e.g. `'ctrl+shift+a'`

Letter keybinds are case-insensitive — `'a'` matches both `a` and `A` (with Shift held).

SEE ALSO
========

  * [Selkie::Widget](Selkie--Widget.md) — widgets receive events via `handle-event`

  * [Selkie::App](Selkie--App.md) — the event loop dispatches to focused widget first, then parent chain, then global keybinds



Category of event. `KeyEvent` for keystrokes, `MouseEvent` for clicks and scrolls, `ResizeEvent` for terminal resizes.



Modifier keys. Test with `$ev.has-modifier(Mod-Ctrl)`, etc.

### has UInt $.id

The keycode or character codepoint of the event. For named keys this is an `NCKEY_*` constant; for printable characters it's the ordinal.

### has Str $.char

The effective printable character, if any. Respects Shift (Shift+1 → `'!'`). Undefined for non-printable keys, synthesised events, and legacy control sequences.

### has Set $.modifiers

The set of modifier keys held when the event fired. Test with `has-modifier`.

### has NcInputType $.input-type

The input type: NCTYPE_PRESS, NCTYPE_RELEASE, NCTYPE_REPEAT, etc. The framework typically filters RELEASE events before dispatching.

### has EventType $.event-type

Which category this event belongs to — see EventType.

### has Int $.y

Mouse Y coordinate for `MouseEvent`, -1 otherwise.

### has Int $.x

Mouse X coordinate for `MouseEvent`, -1 otherwise.

### method has-modifier

```raku
method has-modifier(
    Modifier $mod
) returns Bool
```

True if the given modifier is part of the event's modifier set.

### method has-any-modifier

```raku
method has-any-modifier() returns Bool
```

True if any modifier is held. Useful for "pass bare keys to the widget, bubble modified keys to global keybinds" branches.

### method from-ncinput

```raku
method from-ncinput(
    Notcurses::Native::Types::Ncinput $ni
) returns Selkie::Event
```

Build a `Selkie::Event` from a raw notcurses `Ncinput` struct. Called by `Selkie::App` inside the event loop — you don't normally call this yourself. Handles: resize detection, mouse vs key classification, modifier bit decoding, effective character resolution for Shift + key combos, and legacy Ctrl+A..Z control-code remapping for terminals without the kitty keyboard protocol.

Keybind
=======

A parsed keybind specification, produced by `Keybind.parse` and matched against events via `matches`. You don't normally construct or match these yourself — `on-key` does it for you — but the class is exposed so advanced code can inspect registered binds.

### has UInt $.id

The target keycode / character codepoint.

### has Str $.char

The target character, if the bind was for a single character.

### has Set $.modifiers

The modifier set that must be held for a match.

### has Str $.spec

The original spec string the bind was parsed from. Useful for help-overlay rendering ("Ctrl+L — Lorebooks").

### has Str $.description

Optional human-readable description of what the bind does. Set via the `:description` arg on `Widget.on-key`; surfaced by [Selkie::Widget::HelpOverlay](Selkie--Widget--HelpOverlay.md).

### has Callable &.handler

The handler callable invoked on match.

### method parse

```raku
method parse(
    Str:D $spec,
    &handler,
    Str :$description = ""
) returns Selkie::Event::Keybind
```

Parse a keybind spec string into a `Keybind`. Spec grammar is described under KEYBIND SYNTAX in this module's main pod. Throws on unknown modifiers or unknown key names.

### method matches

```raku
method matches(
    Selkie::Event $ev
) returns Bool
```

Does the given event match this keybind? Letter binds are case-insensitive — `'a'` matches a typed `A` with Shift held. All other binds require an exact modifier-set match.

