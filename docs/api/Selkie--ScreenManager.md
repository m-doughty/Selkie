NAME
====

Selkie::ScreenManager - Named multi-screen management

SYNOPSIS
========

You rarely use `ScreenManager` directly — [Selkie::App](Selkie--App.md)'s `add-screen`, `switch-screen`, and `screen-manager` methods forward to it. When you do need the underlying object (e.g. to enumerate screen names):

```raku
my $sm = $app.screen-manager;

say $sm.active-screen;           # 'main'
say $sm.screen-names;            # ('login', 'main', 'settings')

# Route a keybind based on the active screen
$app.on-key('ctrl+n', -> $ {
    given $app.screen-manager.active-screen {
        when 'tasks' { create-task }
        when 'notes' { create-note }
    }
});
```

DESCRIPTION
===========

A tiny registry mapping screen names to root containers, with one marked as active at a time. `Selkie::App` uses it to park inactive screens off-screen while preserving their state.

Switching screens is fast — the inactive roots remain fully built, just repositioned off-screen. Their widgets keep their state (text input buffers, scroll positions, cursor positions) until the screen is reactivated.

EXAMPLES
========

Checking before registering
---------------------------

```raku
unless $app.screen-manager.has-screen('settings') {
    $app.add-screen('settings', build-settings-screen());
}
```

Cleanup
-------

Remove a screen you no longer need (e.g. after logout). Attempting to remove the active screen throws:

```raku
$app.switch-screen('login');
$app.screen-manager.remove-screen('main');
```

SEE ALSO
========

  * [Selkie::App](Selkie--App.md) — wraps `ScreenManager` with higher-level conveniences

### method add-screen

```raku
method add-screen(
    Str:D $name,
    Selkie::Container $root
) returns Mu
```

Register a screen under a name. If this is the first screen added, it automatically becomes active. Subsequent screens join the registry but the active screen is unchanged. Idempotent by name: re-adding the same name overwrites the previous root.

### method remove-screen

```raku
method remove-screen(
    Str:D $name
) returns Mu
```

Remove a registered screen by name. Fails if the screen is currently active — switch to another screen first. Destroys the screen's root widget tree.

### method switch-to

```raku
method switch-to(
    Str:D $name
) returns Mu
```

Make the named screen active. Marks its root dirty so it re-renders. Fails if no screen with that name exists.

### method active-screen

```raku
method active-screen() returns Str
```

The name of the currently active screen, or `Nil` if no screens are registered.

### method active-root

```raku
method active-root() returns Selkie::Container
```

The root container of the currently active screen, or the type object `Selkie::Container` if no screen is active.

### method screen-names

```raku
method screen-names() returns List
```

Sorted list of registered screen names.

### method screen

```raku
method screen(
    Str:D $name
) returns Selkie::Container
```

Look up a registered screen's root widget by name. Returns the Container type object if no screen with that name exists.

### method has-screen

```raku
method has-screen(
    Str:D $name
) returns Bool
```

True if a screen with the given name is registered.

### method focusable-descendants

```raku
method focusable-descendants() returns Seq
```

Focusable descendants of the active screen's root. Used by `Selkie::App` to build the Tab cycle.

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Propagate a terminal resize to every registered screen, not just the active one. Without this, switching to an inactive screen after a resize would render at stale dimensions until a re-layout happens to fire. Each screen's root is a Container, so its handle-resize cascades through its subtree synchronously.

### method destroy

```raku
method destroy() returns Mu
```

Destroy every registered screen and clear the active screen reference. Called automatically by `Selkie::App.shutdown`.

