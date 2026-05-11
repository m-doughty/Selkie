NAME
====

Selkie::Layout::Allocate - Shared sizing-allocation pass for box layouts

SYNOPSIS
========

```raku
use Selkie::Layout::Allocate;
use Selkie::Sizing;

# A custom container that arranges children along the row axis:
my @allocs = allocate-along-axis(@kids, self.rows);

# `@allocs` is parallel to `@kids`; @allocs[$i] is the cell-count
# the layout assigns to the corresponding child. Position the children
# yourself — Allocate doesn't know about reposition / set-viewport.
```

DESCRIPTION
===========

`allocate-along-axis` runs the three-pass sizing algorithm that both [Selkie::Layout::VBox](Selkie--Layout--VBox.md) and [Selkie::Layout::HBox](Selkie--Layout--HBox.md) use to decide how much room each child gets:

  * **Pass 1.** Walk the children. Children with `Sizing.fixed($n)` take `$n` cells (clamped by remaining space). Children with `Sizing.percent($n)` take `$n%` of the original axis total (also clamped). Flex children defer; their flex factors are accumulated into a running total.

  * **Pass 2.** Distribute whatever space remains among flex children, weighted by their flex factor relative to the total flex weight. Each flex share is floored, so several flex children can leave a few cells unspent.

  * **Pass 3.** Hand any rounding remainder to the highest-index flex child. This keeps the box exactly filled and avoids rounding drift on resizes.

The function returns an `Array[UInt]` aligned with `@kids`; callers are responsible for positioning and propagating viewport bounds, since those depend on which axis is being laid out.

Why a free sub and not a base role?
-----------------------------------

VBox and HBox differ only in axis: VBox stacks rows, HBox stacks columns. Pass 3 (positioning) is axis-specific — it has to call `reposition($cy, 0)` versus `reposition(0, $cx)`, plus `set-viewport` with axis-specific named args. Bridging that into a shared role would obscure the layout code without saving lines, so the extraction stops at the axis-agnostic part: the allocation math.

### sub allocate-along-axis

```raku
sub allocate-along-axis(
    @kids,
    Int $total where { ... }
) returns Array
```

Compute per-child allocations along a single axis, given the total axis size. Returns an Array[UInt] where `@allocs[$i]` is the cell count for `@kids[$i]`. Sum of allocations equals `$total` when flex children are present and `$total` is non-zero; otherwise allocations may sum to less than `$total`. Algorithm: =item Fixed children take `value` cells (clamped by remaining). =item Percent children take `value%` of `$total` (also clamped). =item Flex children share whatever remains, weighted by `value`; the highest-index flex child collects any rounding remainder.

