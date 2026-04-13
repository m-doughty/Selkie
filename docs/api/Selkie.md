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

AUTHOR
======

Matt Doughty <matt@apogee.guru>

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

