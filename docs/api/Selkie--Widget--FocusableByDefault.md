NAME
====

Selkie::Widget::FocusableByDefault - Mix-in role that defaults `focusable` to True at construction

SYNOPSIS
========

```raku
use Selkie::Widget;
use Selkie::Widget::FocusableByDefault;

unit class My::Toggle does Selkie::Widget does Selkie::Widget::FocusableByDefault;

# No `method new` override needed — composing the role causes
# `My::Toggle.new(...)` to default `focusable => True` unless the
# caller passes it explicitly.
```

DESCRIPTION
===========

Most input widgets in Selkie are focusable by default — Buttons, Checkboxes, TextInputs, ListViews, RadioGroups, and so on. Before this role existed, each of those widgets carried the same three-line `new` override:

```raku
method new(*%args --> ::?CLASS) {
    %args<focusable> //= True;
    callwith(|%args);
}
```

That boilerplate is what this role consolidates. Compose it on any widget that should default to focusable, and the role's `new` takes care of the `focusable` default — callers that pass an explicit `:!focusable` or `:focusable(False)` still win, because `//=` respects the caller's choice.

Why a role and not a base class?
--------------------------------

Selkie's widget hierarchy is role-based (everything composes `Selkie::Widget`) rather than class-based, so a role mixin is the natural shape. Composing this role doesn't add any state — only the `new` behaviour — so it's free of the usual diamond-inheritance hazards that come with multi-class hierarchies.

What if my widget needs more constructor logic?
-----------------------------------------------

Implement `submethod TWEAK` on your class — it runs after `new` has returned the new object, with all attributes initialized. The role's `new` doesn't interfere with `TWEAK`; both compose cleanly.

### method new

```raku
method new(
    *%args
) returns Mu
```

Constructor wrapper. Defaults `focusable` to True before delegating to the next `new` candidate in MRO (typically `Mu.new`), which returns an instance of the composing class. An explicit `:focusable(False)` from the caller is preserved. The return type is intentionally unconstrained: a role-context `--` ::?CLASS> trips `Pod::To::Markdown`'s signature renderer (the placeholder has no `.WHICH` before composition), and the constraint would be redundant anyway since `callwith` already returns an instance of `::?CLASS`.

