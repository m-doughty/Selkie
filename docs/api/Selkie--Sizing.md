NAME
====

Selkie::Sizing - Declarative sizing model for widgets

SYNOPSIS
========

```raku
use Selkie::Sizing;

# Exactly 3 rows/cols
my $s1 = Sizing.fixed(3);

# 50% of the parent's available space
my $s2 = Sizing.percent(50);

# Flexible — takes a share of whatever's left after fixed+percent allocations
my $s3 = Sizing.flex;      # flex factor 1
my $s4 = Sizing.flex(2);   # flex factor 2 (twice as much as a flex(1) sibling)
```

DESCRIPTION
===========

Every widget has a `sizing` attribute that tells its parent layout how much space it wants. Layouts (`VBox`, `HBox`) allocate space in three passes:

  * **Pass 1 — fixed**: each `Sizing.fixed(n)` child gets exactly `n` rows (VBox) or cols (HBox).

  * **Pass 2 — percent**: each `Sizing.percent(n)` child gets `n%` of the parent's total size.

  * **Pass 3 — flex**: whatever is left over is distributed proportionally to flex children by their flex factor.

Flex is the common case. Use fixed for header bars, toolbars, status lines. Use percent sparingly — usually flex achieves the same thing more naturally.

EXAMPLES
========

A three-pane layout
-------------------

Top bar is 1 row, bottom bar is 1 row, middle fills the rest.

```raku
my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(text => 'header', sizing => Sizing.fixed(1));
$root.add: $main-content;                                  # sizing => Sizing.flex
$root.add: Selkie::Widget::Text.new(text => 'footer', sizing => Sizing.fixed(1));
```

A weighted split
----------------

Left pane gets one-third, right pane gets two-thirds.

```raku
my $columns = Selkie::Layout::HBox.new(sizing => Sizing.flex);
$columns.add: $sidebar;  # sizing => Sizing.flex(1)
$columns.add: $main;     # sizing => Sizing.flex(2)
```



The three sizing strategies available to widgets. `SizeFixed` — an exact row/col count. `SizePercent` — a percentage of the parent. `SizeFlex` — a share of leftover space after fixed and percent children have been allocated.

class Selkie::Sizing::Sizing
----------------------------

A sizing declaration on a widget. Build one with the factory methods `Sizing.fixed`, `Sizing.percent`, or `Sizing.flex`. You rarely construct this directly with `.new`.

### has SizingMode $.mode

Which sizing strategy to use.

### has Numeric $.value

The numeric parameter for the strategy: row count for fixed, percentage for percent, flex factor for flex.

### method fixed

```raku
method fixed(
    Int $n where { ... }
) returns Selkie::Sizing::Sizing
```

Fixed size in rows (VBox) or columns (HBox). Takes a non-negative integer.

### method percent

```raku
method percent(
    Numeric $n
) returns Selkie::Sizing::Sizing
```

Percent of the parent's available space. Pass any number 0–100.

### method flex

```raku
method flex(
    Numeric $n = 1
) returns Selkie::Sizing::Sizing
```

Flexible share of leftover space. The factor defaults to 1; a flex(2) widget next to a flex(1) widget gets twice as much space. Use plain `Sizing.flex` for most widgets and reserve non-default factors for cases where you genuinely want a 2:1 or 3:1 ratio.

