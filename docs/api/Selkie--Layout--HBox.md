NAME
====

Selkie::Layout::HBox - Arrange children left to right

SYNOPSIS
========

```raku
use Selkie::Layout::HBox;
use Selkie::Sizing;

my $row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$row.add: $label;     # Sizing.fixed(8)
$row.add: $input;     # Sizing.flex
$row.add: $button;    # Sizing.fixed(10)
```

DESCRIPTION
===========

`HBox` arranges children horizontally. Allocation follows the same three-pass sizing rule as [Selkie::Layout::VBox](Selkie--Layout--VBox.md), but operates on columns instead of rows.

All children get the full parent height; only widths are computed.

EXAMPLES
========

Three-column main layout
------------------------

The classic file-manager pattern: sidebar + main + details.

```raku
my $columns = Selkie::Layout::HBox.new(sizing => Sizing.flex);
$columns.add: $sidebar;        # Sizing.fixed(20)
$columns.add: $main-content;   # Sizing.flex
$columns.add: $details;        # Sizing.fixed(30)
```

A button row
------------

```raku
my $buttons = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$buttons.add: Selkie::Widget::Button.new(label => 'Cancel', sizing => Sizing.flex);
$buttons.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(2));   # spacer
$buttons.add: Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.flex);
```

SEE ALSO
========

  * [Selkie::Layout::VBox](Selkie--Layout--VBox.md) — vertical version of the same layout

  * [Selkie::Layout::Split](Selkie--Layout--Split.md) — two-pane split with a divider

  * [Selkie::Sizing](Selkie--Sizing.md) — the sizing model

### method render

```raku
method render() returns Mu
```

Perform layout and render each child. Called automatically by the render cycle. Columns are allocated using the same three-pass strategy as `VBox`, applied to the width axis.

