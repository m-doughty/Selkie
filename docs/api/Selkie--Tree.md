NAME
====

Selkie::Tree - Tree-walking helpers used by widgets that need to reach beyond their own subtree

SYNOPSIS
========

```raku
use Selkie::Tree;

# Mark every widget whose plane intersects this absolute screen rect
# as dirty — used by Image.destroy-blit-plane to repaint cells under
# the removed sprixel.
mark-widgets-in-rect-dirty(
    abs-y => 5,  abs-x => 10,
    rows  => 4,  cols  => 16,
);

# The active modal (or Nil), used by widgets that need to skip
# rendering when occluded.
my $modal = current-active-modal;
```

DESCRIPTION
===========

A small set of free subs that bridge between a widget and the wider tree it lives in, without requiring the widget to walk up to the [Selkie::App](Selkie--App.md) instance manually. [Selkie::App](Selkie--App.md) at init populates two class-level provider closures — one returning the live list of tree roots (active screen + modal stack + toast), the other returning the active modal — and the helpers here read through them.

This pattern keeps widgets like [Selkie::Widget::Image](Selkie--Widget--Image.md) from needing a circular import on Selkie::App while still letting them participate in app-level coordination (cell cleanup after sprixel destroy, modal occlusion checks, etc.).

### sub set-tree-roots-provider

```raku
sub set-tree-roots-provider(
    &p
) returns Nil
```

Set the tree-roots provider — a closure returning an iterable of widget roots. `Selkie::App` calls this during init so tree-walking helpers can find the live trees without each helper needing a direct reference to the app.

### sub current-tree-roots

```raku
sub current-tree-roots() returns List
```

The current list of widget tree roots. Used internally by helpers in this module; apps don't typically call this directly.

### sub set-modal-provider

```raku
sub set-modal-provider(
    &p
) returns Nil
```

Set the active-modal provider — a closure returning the topmost open modal widget or Nil. `Selkie::App` calls this on init.

### sub current-active-modal

```raku
sub current-active-modal() returns Mu
```

The topmost open modal widget, or Nil if no modal is open.

### sub mark-widgets-in-rect-dirty

```raku
sub mark-widgets-in-rect-dirty(
    Int :$abs-y!,
    Int :$abs-x!,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Nil
```

Walk every tree root and mark dirty any widget whose absolute screen bounds intersect the given rectangle. Used by sprixel-bearing widgets after they destroy a blit-plane: the cells under the removed sprixel may belong to a widget that has nothing else changing this frame, so without an explicit dirty mark the widget won't repaint and the cells will continue to show whatever was cached pre-sprixel-removal. Cheap walk; called once per blit teardown.

