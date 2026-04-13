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

