NAME
====

Selkie::Widget::Button - Focusable clickable button

SYNOPSIS
========

```raku
use Selkie::Widget::Button;
use Selkie::Sizing;

my $ok = Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.fixed(1));
$ok.on-press.tap: -> $ { $app.store.dispatch('form/save') };
```

DESCRIPTION
===========

Emits on its `on-press` Supply when the user presses `Enter` or `Space` while focused, or when they primary-click anywhere on the button. Highlights visually while focused. The click path also takes focus first (via [Selkie::App](Selkie--App.md)'s click-to-focus), so a mouse-driven press leaves the button in the same state a keyboard press would.

Focusable by default (no need to pass `focusable =` True>). The label is immutable after construction — build a new button if you need different text.

Debouncing accidental double-clicks
-----------------------------------

Mouse drivers and the terminal layer occasionally deliver two presses for a single physical click. For buttons whose activation has visible side effects (adding a row, kicking off a job, posting a request), pass `:debounce-ms` to throttle the `on-press` emit:

```raku
my $add = Selkie::Widget::Button.new(
    label       => '+ Add row',
    sizing      => Sizing.fixed(14),
    debounce-ms => 120,    # collapse press emits within 120ms
);
```

The default of `0` leaves existing buttons unchanged.

EXAMPLES
========

A button row
------------

```raku
my $row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $save = Selkie::Widget::Button.new(label => 'Save',   sizing => Sizing.flex);
my $undo = Selkie::Widget::Button.new(label => 'Undo',   sizing => Sizing.flex);
$row.add($save);
$row.add($undo);

$save.on-press.tap: -> $ { $app.store.dispatch('doc/save') };
$undo.on-press.tap: -> $ { $app.store.dispatch('doc/undo') };
```

SEE ALSO
========

  * [Selkie::Widget::Checkbox](Selkie--Widget--Checkbox.md) — focusable boolean toggle

  * [Selkie::Widget::ConfirmModal](Selkie--Widget--ConfirmModal.md) — pre-built yes/no dialog using Buttons

### has Str $.label

The text shown on the button. Required at construction; use `set-label` to change afterwards (e.g. for counters).

### has UInt $.debounce-ms

Reject press emits that arrive within this many milliseconds of the previous emit. 0 (default) leaves every press through — the existing contract for every consumer that doesn't opt in. Set on buttons whose activation is destructive or stateful enough that a stray second click would surprise the user (typical mouse-click double- fire, repeat-key bursts). Applies uniformly to mouse and keyboard activation paths.

### method emit-press

```raku
method emit-press() returns Nil
```

Single chokepoint for emit. Centralises the debounce check so the mouse path and the keyboard path can't drift apart.

### method on-press

```raku
method on-press() returns Supply
```

Supply that emits each time the user activates the button (Enter or Space while focused).

### method set-label

```raku
method set-label(
    Str:D $l
) returns Mu
```

Replace the displayed label. Marks the widget dirty.

### method set-focused

```raku
method set-focused(
    Bool $f
) returns Mu
```

Called by `Selkie::App.focus`. You don't usually call this yourself.

### method is-focused

```raku
method is-focused() returns Bool
```

True if the button currently has focus.

