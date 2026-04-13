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

Emits on its `on-press` Supply when the user presses `Enter` or `Space` while focused. Highlights visually while focused.

Focusable by default (no need to pass `focusable =` True>). The label is immutable after construction — build a new button if you need different text.

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

The text shown on the button. Required and immutable.

### method on-press

```raku
method on-press() returns Supply
```

Supply that emits each time the user activates the button (Enter or Space while focused).

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

