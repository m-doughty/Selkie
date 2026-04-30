NAME
====

Selkie::Widget::HelpOverlay - Modal listing keybinds for the focused widget chain

SYNOPSIS
========

```raku
use Selkie::Widget::HelpOverlay;

# Bind globally on the screen root:
$root.on-key: 'ctrl+h', -> $ {
    my $help = Selkie::Widget::HelpOverlay.new(
        app             => $app,
        focused-widget  => $app.focused-widget,
    );
    $app.show-modal($help.build);
};
```

DESCRIPTION
===========

Walks the focused widget and each ancestor up to (and including) the screen root, collecting any `on-key` binds that carry a `:description`. Renders a centred modal grouped by widget class so users can see what shortcuts are reachable from their current focus.

Binds without descriptions are skipped — they're considered internal plumbing (e.g. the editor cursor's character-handling) rather than discoverable shortcuts. Authors opt in by passing `:description` to `Widget.on-key`.

The overlay's modal sets `dismiss-on-click-outside =` True> by default — clicking anywhere outside the help panel closes it. The embedded Close button still works (Enter, Space, or click), and so does Esc. The list itself doesn't yet scroll on overflow; widgets with very long bind lists scroll their owner ScrollView via the standard scroll-wheel routing.

SEE ALSO
========

  * [Selkie::Widget](Selkie--Widget.md) — `on-key` registers binds, `keybinds` reads them

  * [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — the underlying overlay container

### has Mu $.app

App reference. Untyped so snapshot-test stubs can stand in.

### has Selkie::Widget $.focused-widget

The widget that currently has focus. The overlay walks upward from here through its `.parent` chain to gather all reachable keybinds.

### method collect-groups

```raku
method collect-groups() returns List
```

Walk from $!focused-widget up through .parent collecting documented keybinds. Returns a list of { title, binds => [{ spec, description }, ...] } in focused-leaf-first order so the most-immediate context shows first. Widgets with no documented binds are omitted.

