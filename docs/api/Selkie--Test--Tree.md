NAME
====

Selkie::Test::Tree - Find and assert on widgets inside a built tree

SYNOPSIS
========

```raku
use Test;
use Selkie::Test::Tree;
use Selkie::Widget::Button;

# $root is some layout tree built by your app code
my $save-btn = find-widget $root, -> $w {
    $w ~~ Selkie::Widget::Button && $w.label eq 'Save';
};
ok $save-btn.defined, 'Save button exists';

my @all-buttons = find-widgets $root, -> $w { $w ~~ Selkie::Widget::Button };
is @all-buttons.elems, 3, 'three buttons total';

contains-widget-ok $root, $save-btn, 'save button reachable from root';

done-testing;
```

DESCRIPTION
===========

When a widget tree is built by a subscription callback or a factory helper, you often don't hold direct references to every child. These helpers walk the tree (descending through `Container` children and `Border`/`Modal` content) so tests can locate widgets by predicate.

The `walk` function is the underlying iterator; the other helpers build on it. Write `find-widget($root, &pred)` for "first match" and `find-widgets($root, &pred)` for "all matches". The predicate is any `Callable` that takes a widget and returns a truthy value.

EXAMPLES
========

Find by widget type
-------------------

```raku
my $first-input = find-widget $root,
    -> $w { $w ~~ Selkie::Widget::TextInput };
```

Find by attribute
-----------------

```raku
my $title-bar = find-widget $root, -> $w {
    $w ~~ Selkie::Widget::Text && $w.text.starts-with('Settings');
};
```

Assert the tree's shape
-----------------------

```raku
is find-widgets($root, * ~~ Selkie::Widget::Button).elems, 2, 'two buttons';
is find-widgets($root, * ~~ Selkie::Widget::ListView).elems, 1, 'one list';
```

Verify a widget is still reachable
----------------------------------

Useful to catch regressions where a widget gets destroyed but tests still held a reference:

```raku
contains-widget-ok $root, $my-input, 'input still in the tree';
```

SEE ALSO
========

  * [Selkie::Container](Selkie--Container.md) — provides the `children` list `walk` descends through

  * [Selkie::Widget::Border](Selkie--Widget--Border.md), [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — walked through their `content`

### sub walk

```raku
sub walk(
    Selkie::Widget $root
) returns Seq
```

Iterate every widget reachable from `$root`, depth-first. Yields `$root` itself first, then descends through `Container.children` and any `.content` (for Border/Modal). Lazy — safe to short-circuit with `.first`.

### sub find-widget

```raku
sub find-widget(
    Selkie::Widget $root,
    &predicate
) returns Selkie::Widget
```

Return the first widget matching the predicate, or `Nil`. The predicate can be any `Callable` taking a widget; smartmatch also works thanks to Raku's `*` whatever star: find-widget $root, * ~~ Selkie::Widget::Button; find-widget $root, -> $w { $w.focusable };

### sub find-widgets

```raku
sub find-widgets(
    Selkie::Widget $root,
    &predicate
) returns List
```

Return every widget in the tree matching the predicate, in walk order.

### sub contains-widget-ok

```raku
sub contains-widget-ok(
    Selkie::Widget $root,
    Selkie::Widget $target,
    Str:D $desc
) returns Mu
```

Test assertion: `$target` is reachable from `$root`. Uses identity comparison (`===`), so it's checking the same widget instance.

