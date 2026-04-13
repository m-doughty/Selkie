NAME
====

Selkie::Widget::CommandPalette - VS-Code-style fuzzy-filtered action launcher

SYNOPSIS
========

```raku
use Selkie::Widget::CommandPalette;

my $palette = Selkie::Widget::CommandPalette.new;
$palette.add-command(label => 'New note',       -> { create-note });
$palette.add-command(label => 'Quit',           -> { $app.quit });
$palette.add-command(label => 'Toggle theme',   -> { toggle-theme });

my $modal = $palette.build;

# Close the modal and run the command when the user activates one.
$palette.on-command.tap: -> $cmd {
    $app.close-modal;
    $cmd.action.();
};

# Bind Ctrl+P to open the palette
$app.on-key('ctrl+p', -> $ {
    $palette.reset;
    $app.show-modal($modal);
    $app.focus($palette.focusable-widget);
});
```

DESCRIPTION
===========

A modal that slides in a search box over a scrollable action list. Type to filter, arrows to navigate, Enter to run, Esc to cancel. Commands are registered once — each carries a label and an action callback.

Filtering is a simple case-insensitive substring match. Matches are ranked with earlier-position-in-label winning over later-position matches; ties fall back to insertion order. Good enough for action palettes with hundreds of commands, which covers most real use.

The modal closes itself on Enter before invoking the callback — so the callback runs with focus restored to whatever had it before the palette opened. If you need the palette to stay open (e.g. for chained commands), call `$app.show-modal` again from inside the callback.

EXAMPLES
========

App-wide command palette
------------------------

```raku
my $palette = Selkie::Widget::CommandPalette.new;

# Register at startup, wherever your commands live:
$palette.add-command(label => 'Save document',
    -> { $app.store.dispatch('doc/save') });
$palette.add-command(label => 'New document',
    -> { $app.store.dispatch('doc/new') });
$palette.add-command(label => 'Close document',
    -> { $app.store.dispatch('doc/close') });
$palette.add-command(label => 'Toggle dark mode',
    -> { $app.store.dispatch('theme/toggle') });

my $modal = $palette.build;

$app.on-key('ctrl+p', -> $ {
    $palette.reset;                # clear filter + reset selection
    $app.show-modal($modal);
    $app.focus($palette.focusable-widget);
});
```

Contextual palette for a specific screen
----------------------------------------

Build separate palettes for different contexts — e.g. an editor palette distinct from an inbox palette. Register each on a screen-scoped keybind:

```raku
$app.on-key('ctrl+p', :screen('editor'), -> $ {
    $app.show-modal($editor-palette.build);
    $app.focus($editor-palette.focusable-widget);
});

$app.on-key('ctrl+p', :screen('inbox'), -> $ {
    $app.show-modal($inbox-palette.build);
    $app.focus($inbox-palette.focusable-widget);
});
```

SEE ALSO
========

  * [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — underlying modal

  * [Selkie::Widget::FileBrowser](Selkie--Widget--FileBrowser.md) — similar wrapper pattern for file picking

### method on-command

```raku
method on-command() returns Supply
```

Supply emitting the activated `Command` when the user hits Enter on a filtered row. Tap this to close the modal and run the action.

### method add-command

```raku
method add-command(
    &action,
    Str:D :$label!
) returns Mu
```

Register a command. `label` is shown in the list and matched against the user's filter query; the positional `&action` is called with no arguments when the user activates the row. Typical usage puts the action block at the call-site tail: $palette.add-command(label => 'Save', -> { save-document });

### method clear-commands

```raku
method clear-commands() returns Mu
```

Remove every registered command. Useful if commands are context-dependent and the palette is rebuilt on open.

### method reset

```raku
method reset() returns Mu
```

Reset the filter and cursor to fresh state. Call before re-opening the palette so the user starts with the full list.

### method build

```raku
method build(
    Rat :$width-ratio = 0.5,
    Rat :$height-ratio = 0.5
) returns Selkie::Widget::Modal
```

Build the modal and wire its widgets. Call once at setup; cache the returned Modal and pass it to `$app.show-modal` whenever the palette should open. Safe to call multiple times — subsequent calls return the same modal.

### method focusable-widget

```raku
method focusable-widget() returns Mu
```

Which widget should receive initial focus when the modal opens. The TextInput — typing immediately filters without pressing Tab.

