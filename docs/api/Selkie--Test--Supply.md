NAME
====

Selkie::Test::Supply - Observation and assertion helpers for widget Supply emissions

SYNOPSIS
========

```raku
use Test;
use Selkie::Test::Keys;
use Selkie::Test::Supply;
use Selkie::Widget::Button;

my $btn = Selkie::Widget::Button.new(label => 'OK');
$btn.set-focused(True);

# Collect everything a Supply emits during an action
my @emissions = collect-from $btn.on-press, {
    press-key($btn, 'enter');
    press-key($btn, 'space');
};
is @emissions.elems, 2, 'two presses';

# Or assert directly:
emitted-once-ok $btn.on-press, True, 'Enter presses the button', {
    press-key($btn, 'enter');
};

done-testing;
```

DESCRIPTION
===========

Widgets expose user-level events as [Supply](Supply)s — `on-press`, `on-change`, `on-activate`, etc. Testing them without these helpers is a tap-collect-assert dance in every test. This module provides the pattern as three named functions.

Supply emissions from widgets are synchronous — the `.emit` call in a handler fires the tap inline — so `collect-from` works without needing event-loop integration. The tap is closed automatically at the end of the block.

EXAMPLES
========

Count emissions
---------------

```raku
emitted-count-is $list.on-select, 3, 'three cursor moves', {
    press-keys($list, 'down', 'down', 'down');
};
```

Capture and inspect
-------------------

```raku
my @emitted = collect-from $input.on-change, {
    type-text($input, 'hi');
};
is @emitted[*-1], 'hi', 'last emission is the final text';
```

Assert nothing emitted
----------------------

```raku
emitted-count-is $btn.on-press, 0, 'unfocused button ignores key', {
    press-key($btn, 'enter');
};
```

SEE ALSO
========

  * [Selkie::Test::Keys](Selkie--Test--Keys.md) — for synthesising the events that trigger the emissions

  * [Selkie::Test::Store](Selkie--Test--Store.md) — for store-dispatch-based tests

### sub collect-from

```raku
sub collect-from(
    Supply:D $supply,
    &block
) returns List
```

Tap a Supply, run a block, return every emission in order. The tap is closed when the block finishes. Emissions are collected in the same thread, so this works for widget Supplies that emit synchronously from event handlers.

### sub emitted-once-ok

```raku
sub emitted-once-ok(
    Supply:D $supply,
    $expected,
    Str:D $desc,
    &block
) returns Mu
```

Assertion: the supply emitted exactly once, with the given value, during the block. Produces two test lines — one for the count, one for the value (only if the count was 1).

### sub emitted-count-is

```raku
sub emitted-count-is(
    Supply:D $supply,
    Int:D $n,
    Str:D $desc,
    &block
) returns Mu
```

Assertion: the supply emitted exactly `$n` times during the block. `$n` may be 0 to assert nothing was emitted.

