NAME
====

Selkie - High-level TUI framework built on Notcurses

SYNOPSIS
========

```raku
use Selkie;

my $app = Selkie::App.new;
my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

my $log = Selkie::Widget::TextStream.new(sizing => Sizing.flex);
$root.add($log);
$log.append('Hello, Selkie!');

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;
```

DESCRIPTION
===========

`Selkie` is the umbrella module — `use Selkie` imports everything in one go, so you can refer to any class by its full name. Most apps work fine with this; finer-grained imports are available if you prefer to be explicit about what's in scope.

The framework itself is organised into several subnamespaces:

  * **Core** — [Selkie::App](Selkie--App.md), [Selkie::Widget](Selkie--Widget.md), [Selkie::Container](Selkie--Container.md), [Selkie::Store](Selkie--Store.md), [Selkie::ScreenManager](Selkie--ScreenManager.md)

  * **Support types** — [Selkie::Sizing](Selkie--Sizing.md), [Selkie::Style](Selkie--Style.md), [Selkie::Theme](Selkie--Theme.md), [Selkie::Event](Selkie--Event.md)

  * **Layouts** — [Selkie::Layout::VBox](Selkie--Layout--VBox.md), [Selkie::Layout::HBox](Selkie--Layout--HBox.md), [Selkie::Layout::Split](Selkie--Layout--Split.md)

  * **Display widgets** — [Selkie::Widget::Text](Selkie--Widget--Text.md), [Selkie::Widget::RichText](Selkie--Widget--RichText.md), [Selkie::Widget::TextStream](Selkie--Widget--TextStream.md), [Selkie::Widget::Image](Selkie--Widget--Image.md), [Selkie::Widget::ProgressBar](Selkie--Widget--ProgressBar.md)

  * **Input widgets** — [Selkie::Widget::TextInput](Selkie--Widget--TextInput.md), [Selkie::Widget::MultiLineInput](Selkie--Widget--MultiLineInput.md), [Selkie::Widget::Button](Selkie--Widget--Button.md), [Selkie::Widget::Checkbox](Selkie--Widget--Checkbox.md), [Selkie::Widget::RadioGroup](Selkie--Widget--RadioGroup.md), [Selkie::Widget::Select](Selkie--Widget--Select.md)

  * **List widgets** — [Selkie::Widget::ListView](Selkie--Widget--ListView.md), [Selkie::Widget::CardList](Selkie--Widget--CardList.md), [Selkie::Widget::ScrollView](Selkie--Widget--ScrollView.md)

  * **Chrome widgets** — [Selkie::Widget::Border](Selkie--Widget--Border.md), [Selkie::Widget::Modal](Selkie--Widget--Modal.md), [Selkie::Widget::ConfirmModal](Selkie--Widget--ConfirmModal.md), [Selkie::Widget::FileBrowser](Selkie--Widget--FileBrowser.md), [Selkie::Widget::Toast](Selkie--Widget--Toast.md)

Start with [Selkie::App](Selkie--App.md) for the big picture, [Selkie::Widget](Selkie--Widget.md) if you want to write your own widgets, and [Selkie::Store](Selkie--Store.md) for the reactive state model. Every module has runnable examples in its Pod.

MOUSE SUPPORT
=============

Selkie has first-class mouse support across every prebuilt widget. You don't need to opt in — [Selkie::App](Selkie--App.md) enables button + drag events on construction (via `notcurses_mice_enable`), and the dispatcher routes presses, drags, releases, and the scroll wheel through the same `handle-event` path as keystrokes.

Dispatch model
--------------

  * **Keyboard** goes to the focused widget, then ancestors, then global keybinds (unchanged).

  * **Mouse** goes to the deepest widget under the cursor, then ancestors, then global keybinds.

  * A primary press on a focusable widget gives it focus before the event is delivered, so mouse-driven activation matches keyboard-driven activation.

  * **Drag capture**: a press on widget X routes subsequent drag and release events for that button to X, regardless of where the cursor is. This is what makes scrollbar drags and text-selection drags feel right when the cursor leaves the widget.

  * **Modal isolation**: clicks outside the active modal are dropped by default. Modals can opt in to dismiss-on-click-outside by passing `:dismiss-on-click-outside` to their constructor — [Selkie::Widget::HelpOverlay](Selkie--Widget--HelpOverlay.md) uses this.

Per-widget API
--------------

Same registration ergonomics as [Selkie::Widget](Selkie--Widget.md)'s `on-key`:

```raku
# Click anywhere on the widget — primary button by default.
$widget.on-click: -> $ev {
    say "clicked at row {$widget.local-row($ev)}, col {$widget.local-col($ev)}";
};

# Right-click via :button(3); :button(0) catches any button.
$widget.on-click: -> $ev { open-context-menu }, button => 3;

# Scroll wheel.
$widget.on-scroll: -> $ev {
    given $ev.id {
        when NCKEY_SCROLL_UP   { ... }
        when NCKEY_SCROLL_DOWN { ... }
    }
};

# Drag (press + motion-with-button-held). Capture keeps these flowing
# even when the cursor leaves the widget's bounds.
$widget.on-drag: -> $ev {
    say "drag now at row {$ev.y - $widget.abs-y}";
};

# Low-level escape hatches — fire on every press / release.
$widget.on-mouse-down: -> $ev { ... };
$widget.on-mouse-up:   -> $ev { ... };
```

`self.local-row($ev)` and `self.local-col($ev)` translate the event's absolute screen coordinates into widget-local cells (returning `-1` if the event is out of bounds). `contains-point(y, x)` exposes the same hit-test the framework uses internally.

Multi-click
-----------

Press events are annotated with their multiplicity in `$ev.click-count`: 1 for a single click, 2 for a double-click, 3 for a triple-click. The framework counts a press as a continuation of the previous click when it lands on the same cell with the same button within 300 ms. [Selkie::Widget::TextInput](Selkie--Widget--TextInput.md) uses double / triple click to select word / all; [Selkie::Widget::FileBrowser](Selkie--Widget--FileBrowser.md) uses double-click to descend into directories; [Selkie::Widget::ListView](Selkie--Widget--ListView.md) uses double-click to fire `on-activate`.

Built-in widget behaviours
--------------------------

  * **Button**, **Checkbox** — primary click activates / toggles.

  * **TabBar** — primary click activates the tab under the cursor.

  * **RadioGroup**, **ListView**, **Table** — single-click selects the row; scroll wheel moves the cursor. Table also clicks the column header to cycle sort. ListView and Table fire `on-activate` on double-click.

  * **Select** — click toggles the dropdown; scroll wheel scrolls the open dropdown; click on a dropdown row commits.

  * **TextInput**, **MultiLineInput** — click positions the caret; drag selects; double-click selects the word; triple-click selects the line / buffer; Ctrl+A selects all; Ctrl+C / Ctrl+X emit on `on-copy` / `on-cut` (the framework doesn't own the system clipboard — wire OSC 52 / notcurses paste-buffer in your app).

  * **CardList** — click selects the card under the cursor; scroll wheel moves between cards.

  * **ScrollView**, **TextStream** — scroll wheel scrolls; drag on the scrollbar column drags the thumb.

  * **ConfirmModal**, **CommandPalette**, **FileBrowser** — clicks fall through to the embedded Button / ListView / TextInput, which handle them with their built-in behaviour.

  * **HelpOverlay** — click outside dismisses; click the Close button to close.

Display-only widgets (Text, RichText, Image, Border, ProgressBar, Spinner, Toast, Legend, all charts) don't react to mouse — Border passes through to its content.

AUTHOR
======

Matt Doughty <matt@apogee.guru>

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

