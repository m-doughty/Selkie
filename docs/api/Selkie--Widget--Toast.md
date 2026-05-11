NAME
====

Selkie::Widget::Toast - Transient overlay notification

SYNOPSIS
========

You normally use `$app.toast(...)` which manages the widget for you:

```raku
$app.toast('Settings saved');
$app.toast('Connection lost', duration => 5e0);
```

Direct construction is rarely needed.

DESCRIPTION
===========

A centered single-line message bar that auto-dismisses. By convention rendered near the bottom of the screen.

Unlike most widgets, Toast does **not** own a backing plane covering its full area — that would obscure the widgets behind it. Instead it manages a small inline plane, created on `show` and destroyed on hide, attached directly to the parent stdplane via `attach`.

The `Selkie::App.toast` wrapper hides these details: it lazily constructs the widget, calls `attach`, and ensures the correct size on each invocation.

EXAMPLES
========

Custom styling
--------------

```raku
# Red warning style
$app.store.subscribe-with-callback(
    'errors',
    -> $s { $s.get-in('error') // '' },
    -> $msg {
        if $msg.chars > 0 {
            $app.toast($msg);   # default blue-highlight style
        }
    },
    $some-widget,
);
```

SEE ALSO
========

  * [Selkie::App](Selkie--App.md) — `toast(...)` wrapper is the normal entry point

### method attach

```raku
method attach(
    Notcurses::Native::Types::NcplaneHandle $parent-plane,
    Int :$rows where { ... },
    Int :$cols where { ... }
) returns Mu
```

Attach to the standard plane. Called once by `Selkie::App` in place of the usual `init-plane` — Toast lives outside the widget tree (so it can paint on top of any screen and any modal) so it doesn't adopt a plane of its own; the toast-plane is created lazily in `render` on first show.

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Toast lives at screen-top, outside the widget tree, so it doesn't receive the normal handle-resize cascade from containers. App calls this directly when the terminal resizes so the toast-plane sits at the correct width.

### method resize-screen

```raku
method resize-screen(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Back-compat alias. Deprecated — prefer handle-resize.

### method show

```raku
method show(
    Str:D $message,
    Num :$duration = 2e0,
    Selkie::Style :$style = Code.new
) returns Mu
```

Show a toast message for `:duration` seconds. Re-callable while a toast is already showing — the new message replaces the old and the duration restarts from now. Apps don't usually call this directly; prefer `$app.toast(...)` which routes here.

### method is-visible

```raku
method is-visible() returns Bool
```

True while a toast is currently being shown (between `show` and the next `tick` that observes the duration has expired).

### method tick

```raku
method tick() returns Bool
```

Advance the toast's lifetime clock. Called once per frame by `Selkie::App`. When the duration has elapsed, the toast flips to invisible and its plane is destroyed. Returns `True` when visibility *just transitioned* from visible to invisible this tick — the caller (`Selkie::App`) treats that as a signal to force one more composite render so the toast is actually erased from the terminal. Returns `False` otherwise (toast is still visible, or was never visible this tick).

### method destroy

```raku
method destroy() returns Mu
```

Tear down the toast plane. Called by `Selkie::App.shutdown`; apps don't usually call this directly.

