NAME
====

Selkie::Container - Role for widgets that hold child widgets

SYNOPSIS
========

A minimal custom container that stacks its children vertically with a one-row gap between them:

```raku
use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class My::GapBox does Selkie::Container;

method render() {
    my $y = 0;
    for self.children -> $child {
        if $child.plane {
            $child.reposition($y, 0);
            $child.resize($child.sizing.value, self.cols);
        } else {
            $child.init-plane(
                self.plane,
                y => $y, x => 0,
                rows => $child.sizing.value,
                cols => self.cols,
            );
        }
        $child.render;
        $y += $child.sizing.value + 1;   # leave a 1-row gap
    }
    self.clear-dirty;
}
```

DESCRIPTION
===========

`Selkie::Container` layers on top of [Selkie::Widget](Selkie--Widget.md) (`also does Selkie::Widget`). Compose it for any widget that owns child widgets — layouts (`VBox`, `HBox`, `Split`), decorators (`Border`, `Modal`), scrollers (`ScrollView`).

The role provides:

  * A `children` list, manipulated via `add`, `remove`, `clear`

  * Automatic store propagation to added children

  * Recursive destruction and subscription cleanup on `remove` / `clear`

  * A `focusable-descendants` walker so `Selkie::App` can build the Tab cycle

  * A `!render-children` helper that cascades dirty flags for correct subtree redraws

Your container's job is to implement `render`, which positions and sizes each child before rendering it. For typical layouts, lean on `VBox`/`HBox`/`Split` instead of building your own container from scratch.

EXAMPLES
========

Adding and removing children
----------------------------

```raku
my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
my $header = Selkie::Widget::Text.new(text => 'Hi', sizing => Sizing.fixed(1));
$vbox.add($header);

# Later — remove cleans up the widget's plane, subscriptions, and children
$vbox.remove($header);
```

Rebuilding from scratch
-----------------------

```raku
$vbox.clear;                            # destroys all children
$vbox.add($new-a);
$vbox.add($new-b);
```

Writing your own container
--------------------------

If the built-in layouts don't fit, compose `Selkie::Container` directly and implement `render`. Use `!render-children` (inherited) to cascade dirty flags and render each child — this ensures subtree correctness when the container is dirty:

```raku
method render() {
    self!layout-children;      # your own positioning logic
    self!render-children;      # handles dirty cascade + per-child render
    self.clear-dirty;
}
```

SEE ALSO
========

  * [Selkie::Widget](Selkie--Widget.md) — the base role `Container` builds on

  * [Selkie::Layout::VBox](Selkie--Layout--VBox.md), [Selkie::Layout::HBox](Selkie--Layout--HBox.md), [Selkie::Layout::Split](Selkie--Layout--Split.md) — the built-in containers

  * [Selkie::Widget::Border](Selkie--Widget--Border.md), [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — decorators that also compose `Container`

### method children

```raku
method children() returns List
```

The current list of children, in insertion order. Immutable list — to modify, use `add`, `remove`, or `clear`.

### method add

```raku
method add(
    Selkie::Widget $child
) returns Selkie::Widget
```

Add a child widget. The child's `parent` is set, the store is propagated to it (and its subtree), and the container is marked dirty. Returns the added child for chaining.

### method remove

```raku
method remove(
    Selkie::Widget $child
) returns Mu
```

Remove and destroy a specific child. Unsubscribes the child and its entire subtree from the store before destroying. No-op if the given widget isn't actually a child.

### method clear

```raku
method clear() returns Mu
```

Remove and destroy every child. Useful before rebuilding the container's contents from scratch (e.g. in a subscription callback that regenerates a list).

### method render-children

```raku
method render-children() returns Mu
```

Render each child, cascading dirty to the whole subtree if the container itself is dirty. This is the rendering helper you almost always want in a custom container's `render` method — it handles the "parent dirty ⇒ children also need redrawing" rule correctly. Private so composed classes can call it as `self!render-children`.

### method focusable-descendants

```raku
method focusable-descendants() returns Seq
```

Depth-first sequence of focusable descendants. Used by `Selkie::App` to build the Tab/Shift-Tab cycle. Walks children recursively, yielding any whose `focusable` is True. Override if your container needs a non-standard traversal order.

### method destroy

```raku
method destroy() returns Mu
```

Destroy the container and every child recursively. Called automatically when the widget goes out of scope or its parent calls `remove`.

