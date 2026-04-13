NAME
====

Selkie::Layout::Split - Two-pane layout with a divider

SYNOPSIS
========

```raku
use Selkie::Layout::Split;
use Selkie::Sizing;

my $split = Selkie::Layout::Split.new(
    orientation => 'horizontal',   # left | right
    ratio       => 0.3,            # 30% | 70%
    sizing      => Sizing.flex,
);
$split.set-first($sidebar);
$split.set-second($main);
```

DESCRIPTION
===========

Split divides its area into exactly two panes with a one-cell divider between them. The `ratio` attribute controls the split — `0.3` means the first pane takes 30% of the space, the second gets the rest (minus one cell for the divider).

Two orientations:

  * `'horizontal'` — left and right panes, divided by a vertical bar

  * `'vertical'` — top and bottom panes, divided by a horizontal bar

Unlike VBox/HBox which take a list of children, Split takes exactly two content widgets via `set-first` and `set-second`. Each assignment destroys the previous occupant of that slot — use a container widget (like another VBox) on each side if you need more than one widget per pane.

EXAMPLES
========

Sidebar + main content
----------------------

A classic two-pane layout with a 25/75 split:

```raku
my $split = Selkie::Layout::Split.new(
    orientation => 'horizontal',
    ratio       => 0.25,
    sizing      => Sizing.flex,
);
$split.set-first($sidebar-list);
$split.set-second($detail-view);
```

Editor + preview (vertical split)
---------------------------------

Top half is the editor, bottom half is the live preview:

```raku
my $split = Selkie::Layout::Split.new(
    orientation => 'vertical',
    ratio       => 0.5,
    sizing      => Sizing.flex,
);
$split.set-first($editor);
$split.set-second($preview);
```

Multiple widgets per pane
-------------------------

Wrap each side in its own layout:

```raku
my $left = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$left.add($search-input);     # fixed(1)
$left.add($result-list);      # flex

$split.set-first($left);
$split.set-second($details);
```

SEE ALSO
========

  * [Selkie::Layout::VBox](Selkie--Layout--VBox.md), [Selkie::Layout::HBox](Selkie--Layout--HBox.md) — N-child stacked layouts

  * [Selkie::Theme](Selkie--Theme.md) — `divider` slot controls divider appearance

### has Rat $.ratio

The fraction of space given to the first pane. `0.5` is an even split; `0.3` gives 30% to the first pane, 70% to the second. Can be changed at runtime — just mark the Split dirty and re-layout.

### has Str $.orientation

Either `'horizontal'` (left+right panes, vertical divider) or `'vertical'` (top+bottom panes, horizontal divider).

### has Selkie::Widget $.first

The first (left or top) pane's widget. Set via `set-first`.

### has Selkie::Widget $.second

The second (right or bottom) pane's widget. Set via `set-second`.

### method set-first

```raku
method set-first(
    Selkie::Widget $w
) returns Selkie::Widget
```

Install a widget in the first pane. The previous occupant (if any) is destroyed. Returns the new widget for chaining.

### method set-second

```raku
method set-second(
    Selkie::Widget $w
) returns Selkie::Widget
```

Install a widget in the second pane. The previous occupant is destroyed. Returns the new widget for chaining.

