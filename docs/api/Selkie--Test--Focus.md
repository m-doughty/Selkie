NAME
====

Selkie::Test::Focus - Focus simulation for widget tests without a real App

SYNOPSIS
========

```raku
use Test;
use Selkie::Test::Keys;
use Selkie::Test::Focus;
use Selkie::Widget::TextInput;

my $input = Selkie::Widget::TextInput.new;

# Run a block with the input focused — auto-unfocused after:
with-focus $input, {
    type-text($input, 'hello');
    press-key($input, 'enter');
};

is $input.text, 'hello', 'input received keystrokes while focused';
nok $input.is-focused, 'focus released after block';
```

DESCRIPTION
===========

Most focusable widgets gate `handle-event` on `is-focused`:

    return False unless $!focused;

Writing that test setup (`$w.set-focused(True)` + `$w.set-focused(False)`) for every widget test gets repetitive and hides the real intent. The `with-focus` block helper manages the focus state for you.

For widgets that don't have a `set-focused` method (e.g. display-only widgets), `with-focus` is a no-op — the block still runs.

If you want to test multi-widget focus scenarios (like Tab cycling), the App's `focus` and `focus-next` methods are the right API — use those directly with a real `Selkie::App`. This module is for single-widget unit tests.

EXAMPLES
========

Assert focus-gated behaviour
----------------------------

```raku
my $btn = Selkie::Widget::Button.new(label => 'OK');

# Unfocused: key press ignored
my @unfocused = collect-from $btn.on-press, {
    press-key($btn, 'enter');
};
is @unfocused.elems, 0, 'unfocused button ignores Enter';

# Focused: key press consumed
my @focused = collect-from $btn.on-press, {
    with-focus $btn, {
        press-key($btn, 'enter');
    };
};
is @focused.elems, 1, 'focused button fires on Enter';
```

Exception-safe
--------------

`with-focus` restores the unfocused state even if the block throws:

```raku
with-focus $widget, {
    die 'something broke';   # focus is still released after
};
CATCH { default { } }
nok $widget.is-focused, 'focus released despite exception';
```

SEE ALSO
========

  * [Selkie::App](Selkie--App.md) — `focus`, `focus-next`, `focus-prev` for multi-widget focus

  * [Selkie::Test::Keys](Selkie--Test--Keys.md) — synthesise keys to dispatch inside the with-focus block

### sub with-focus

```raku
sub with-focus(
    Selkie::Widget $widget,
    &block
) returns Mu
```

Run a block with the widget marked focused. If the widget has a `set-focused(Bool)` method it's called with True before the block and False after (including on exception). Widgets without that method — e.g. display-only widgets — are passed through unchanged. Closes over the block with `LEAVE` so focus is released even if the block throws.

