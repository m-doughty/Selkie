NAME
====

Selkie::App - The main entry point: event loop, screens, modals, toasts, focus

SYNOPSIS
========

```raku
use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Widget::Text;
use Selkie::Sizing;

my $app = Selkie::App.new;

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(
    text   => 'Hello from Selkie',
    sizing => Sizing.fixed(1),
);

$app.add-screen('main', $root);
$app.switch-screen('main');

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;   # blocks until quit
```

DESCRIPTION
===========

`Selkie::App` is what you construct to start a Selkie program. It owns the notcurses handle, the reactive store, the screen manager, the active modal (if any), the toast overlay, the focused widget, and the event loop.

Your app code:

  * Builds a widget tree

  * Registers it as a screen with `add-screen`

  * Activates a screen with `switch-screen`

  * Picks an initial focused widget with `focus`

  * Registers global keybinds with `on-key`

  * Starts the loop with `run`

The loop wakes on a 16ms input timeout (up to 60 Hz). Each wake it polls for input, dispatches events (to the focused widget, then up the parent chain, then to global keybinds), runs registered frame callbacks, ticks the store, processes any queued focus cycling, ticks the toast, and renders dirty widgets. Idle work is minimized: when nothing changed, the store's subscription walk and the composite render to the terminal are both skipped.

`run` only returns when `quit` is called or an unhandled exception reaches the top of the loop. In either case the terminal is restored before the program exits.

Theme background
----------------

When constructed with a `theme`, `Selkie::App` paints the notcurses standard plane's base cell from `$theme.base` during init so any region no widget writes to falls through to the theme background rather than the terminal's own default. Combined with `Selkie::Widget` doing the same per-plane on `init-plane` / `set-theme` / each `apply-style`, this gives themed backgrounds full-terminal coverage — no gaps between widgets or at screen edges.

The standard plane itself is exposed via `stdplane` if you need to reach it directly (e.g. to paint a custom base cell from application code).

Default keybinds
----------------

`Selkie::App` registers these out of the box so you don't have to:

  * `Tab` / `Shift-Tab` — cycle focus through focusable descendants

  * `Esc` — close the active modal (no-op if none)

  * `Ctrl+Q` — quit the app

Your own `on-key` registrations don't override these by default — if you need to, register your handler with a matching spec and call `quit` or `close-modal` yourself.

LIFECYCLE
=========

Construction calls `notcurses_init`, enables mouse support, drains any pending terminal-query responses, and registers the default keybinds. If `notcurses_init` fails, construction throws immediately.

An `END` phaser registered during construction guarantees `shutdown` runs even if the program exits abnormally (e.g. an exception before `run` is called). This means your terminal is always restored.

`run` wraps the event loop in a `CATCH` block. If anything inside the loop throws, the terminal is restored, the error is printed to STDERR with a full backtrace, and the process exits with code 1.

EXAMPLES
========

A single-screen app
-------------------

The simplest pattern. One screen, one focused input, a quit binding:

```raku
use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Widget::TextInput;
use Selkie::Sizing;

my $app = Selkie::App.new;

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
my $input = Selkie::Widget::TextInput.new(sizing => Sizing.fixed(1));
$root.add($input);

$app.add-screen('main', $root);
$app.switch-screen('main');
$app.focus($input);

$input.on-submit.tap: -> $text { $app.toast("You typed: $text") };

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;
```

Multiple screens
----------------

Register each screen with a name; switch between them with `switch-screen`. The inactive screens are parked off-screen but keep their state (widget instances, focus, scroll position):

```raku
$app.add-screen('login', $login-root);
$app.add-screen('main',  $main-root);

# Start on login:
$app.switch-screen('login');
$app.focus($login-form.password-input);

# Later, after authentication:
$app.switch-screen('main');
$app.focus($main-root.focusable-descendants.List[0]);
```

A modal dialog
--------------

Show a modal to ask the user a question. The modal traps focus — all keystrokes go to it or its descendants until closed — and `Esc` closes it automatically:

```raku
use Selkie::Widget::ConfirmModal;

my $cm = Selkie::Widget::ConfirmModal.new;
$cm.build(
    title     => 'Really delete?',
    message   => "This cannot be undone.",
    yes-label => 'Delete',
    no-label  => 'Cancel',
);
$cm.on-result.tap: -> Bool $confirmed {
    $app.close-modal;
    delete-item() if $confirmed;
};

$app.show-modal($cm.modal);
$app.focus($cm.no-button);    # default to the safe button
```

A frame callback for animation
------------------------------

`on-frame` fires on every iteration of the event loop (~60fps), even when there's no input. Use it to drive timers, animations, or pull from an external stream:

```raku
$app.on-frame: {
    $progress-bar.tick;           # indeterminate animation
    $chat-view.pull-tokens;       # pull from an LLM stream
};
```

Screen-scoped keybinds
----------------------

Scope a keybind to one screen by passing `:screen`. It fires only when that screen is active:

```raku
$app.on-key('ctrl+n', :screen('tasks'), -> $ { create-task });
$app.on-key('ctrl+n', :screen('notes'), -> $ { create-note });
$app.on-key('ctrl+q', -> $ { $app.quit });   # unscoped = every screen
```

SEE ALSO
========

  * [Selkie::Widget](Selkie--Widget.md) — the base role every widget composes

  * [Selkie::ScreenManager](Selkie--ScreenManager.md) — multi-screen management (used via `add-screen` / `switch-screen`)

  * [Selkie::Store](Selkie--Store.md) — the reactive state store `Selkie::App` owns

  * [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — modal dialogs

  * [Selkie::Event](Selkie--Event.md) — the keyboard / mouse event abstraction

### method stdplane

```raku
method stdplane() returns Notcurses::Native::Types::NcplaneHandle
```

The notcurses standard plane — the root of the compositing tree, with the terminal's full dimensions. Exposed for apps that need to set a base cell (fill colour for otherwise-empty cells) so a theme background reaches every corner. Only valid after `run` has initialised notcurses.

### has Selkie::Theme $.theme

The theme installed on every screen's root. Defaults to `Selkie::Theme.default` if not provided to `.new`.

### has Selkie::Store $.store

The reactive store owned by this app. Constructed automatically on `.new`; every screen added to the app gets this store propagated into its widget tree. Subscribe to state paths from widgets via `self.subscribe(...)`.

### has Num $.hot-hz

Hot-rate frame budget in Hz. The main loop caps itself at this rate while anything is happening; the idle ladder then steps down (to 30 / 12 / 4 Hz) after periods of inactivity. Defaults to 60 Hz — enough for smooth typing and scrolling without burning battery on passive sits. Apps doing terminal video playback, high-refresh animations, or live plot rendering can bump this higher — notcurses itself supports video, so 120 Hz+ is a legitimate use case for that flavour of app. This is a CEILING, not a floor: the loop sleeps at least `1 / $hot-hz` seconds between frames, but may sleep longer when the idle ladder has ramped down.

### has Str $.error-log

Path to a file that receives everything that would normally hit stderr while the app is running — Raku warnings (`Use of uninitialized value …`), runtime failures logged via `note`, C-level libraries writing to stderr, notcurses internal diagnostics, etc. Without this, warnings splat into the TUI compositor's cell grid and produce visible garbage that stays on screen until the next full repaint — a TUI can't share stderr with its own drawing surface. When set, `Selkie::App` uses `dup2(2)` on construction to point file descriptor 2 at this file (append mode); the saved copy of the original stderr is restored on `shutdown`. Parent directory is auto-created. A new "=== session …" banner is written at the top of each run so long-lived log files stay navigable. Leave as `Str` (the type object) to disable the redirect — then stderr goes where it would normally.

### method screen-manager

```raku
method screen-manager() returns Selkie::ScreenManager
```

The screen manager. Useful for `.active-screen` and `.screen-names` — you don't typically need to manipulate it directly, since the `add-screen` and `switch-screen` methods on `Selkie::App` are preferred.

### method focused

```raku
method focused() returns Selkie::Widget
```

The widget that currently has focus, or `Nil` if none.

### method event-supply

```raku
method event-supply() returns Supply
```

A Supply that emits every event received by the app. Tap this for global event logging, analytics, or cross-cutting behaviour that doesn't fit the per-widget handler model.

### method root

```raku
method root() returns Selkie::Container
```

Convenience accessor for the active screen's root container. Equivalent to `$app.screen-manager.active-root`. Returns `Nil` if no screen is active.

### method set-theme

```raku
method set-theme(
    Selkie::Theme:D $theme
) returns Mu
```

Swap the active theme at runtime. Updates the app's theme attribute, repaints the stdplane base cell, cascades `set-theme` to every registered screen's root widget (which in turn walks their subtrees), and marks every screen dirty so the next frame re-renders with the new palette. App consumers that hold their own cached Style objects derived from a theme's slots still need to rebuild those — set-theme can't reach closures that copied style values at construction time. The primary guarantee here is "every plane's base cell and every widget's inherited theme updates"; cached styles at the consumer layer are the consumer's responsibility.

### method add-screen

```raku
method add-screen(
    Str:D $name,
    Selkie::Container $root
) returns Mu
```

Register a screen under a name. The screen's root container is attached to the theme, the store, and the notcurses stdplane, then parked either at origin (if it's the first screen added) or off-screen (for subsequent screens — `switch-screen` will move it to origin when activated). Re-registering a name (common pattern: an overlay screen rebuilt each time it opens) discards any stashed per-screen focus from the previous incarnation — that widget is about to be destroyed.

### method switch-screen

```raku
method switch-screen(
    Str:D $name
) returns Mu
```

Activate a registered screen by name. The previously-active screen is parked off-screen; the new one is moved to the origin, resized to full terminal dimensions, and marked dirty so its entire subtree renders fresh on the next frame. Focus follows the user: before switching, the outgoing screen's focused widget is stashed in per-screen focus memory (if it's still attached to that screen's tree). On arrival, the incoming screen's last-focused widget is restored — or, if the screen has never been visited (or the saved reference went stale), focus lands on the first focusable widget in the new tree. Apps don't need to manage focus across screen transitions themselves.

### method set-title

```raku
method set-title(
    Str:D $title
) returns Mu
```

Set the terminal window title via OSC 0 ("icon name + window title"). Writes directly to `/dev/tty` to bypass notcurses's output buffering -- the stdplane's double-buffered render path can otherwise stomp interleaved escape sequences. Handles three common cases: =item Bare terminal -- emits `ESC]0;TITLE BEL`. =item Inside tmux (`$TMUX` set) -- wraps in the DCS passthrough (`ESC Ptmux; ... ESC \\`) so the host terminal actually sees it. Requires `set -g allow-passthrough on` in tmux >= 3.3, which is the default from 3.4 onward. =item No `/dev/tty` available (tests, piped stdin) -- silently no-op. Control characters (ESC, BEL, CR, LF) in `$title` are stripped before emission so a hostile title string can't terminate the sequence early or inject further escapes.

### method build-title-osc

```raku
method build-title-osc(
    Str:D $title,
    Bool :$tmux = Bool::False
) returns Str
```

Build the OSC sequence for a title. Factored out as a class method so tests can exercise the sanitisation + tmux-passthrough logic without needing a real tty. Public for callers that want to emit the sequence elsewhere (logging, snapshot tests, etc).

### method toast

```raku
method toast(
    Str:D $message,
    Num :$duration = 2e0
) returns Mu
```

Show a temporary message bar at the bottom of the screen. It auto-dismisses after `$duration` seconds (default 2). The toast overlay is created lazily on first call — subsequent toasts reuse the same widget.

### method show-modal

```raku
method show-modal(
    Selkie::Widget::Modal $modal
) returns Mu
```

Show a modal dialog. The currently-focused widget is remembered and restored when the modal closes. While a modal is open, all events are routed through it (focus trap); only `Tab`, `Shift-Tab`, and `Esc` reach the app's global keybinds.

### method close-modal

```raku
method close-modal() returns Mu
```

Close the active modal, restore the pre-modal focus target, and mark the entire active screen dirty so every widget re-renders over the area that was covered. No-op if no modal is open. The pre-modal focus target is validated against the live tree before restoration — if the widget was destroyed while the modal was open (e.g. the modal's action removed the previously-focused row from a list), focus falls through to the first focusable on the active screen instead of dangling.

### method has-modal

```raku
method has-modal() returns Bool
```

True while a modal is currently being displayed.

### method on-key

```raku
method on-key(
    Str:D $spec,
    &handler,
    Str :$screen
) returns Mu
```

Register a global keybind. The spec is a string matching [Selkie::Event](Selkie--Event.md)'s syntax (`'ctrl+q'`, `'f1'`, `'ctrl+shift+a'`, etc). Pass `:screen` to scope the bind to a single named screen — it will only fire when that screen is active. Leave `:screen` unset for a truly global bind like Ctrl+Q for quit. Global keybinds must include a modifier (Ctrl, Alt, Super) to avoid clashing with text input. Bare character binds belong on focusable widgets that own the key.

### method on-frame

```raku
method on-frame(
    &callback
) returns Mu
```

Register a callback that fires once per frame (~60 times per second), regardless of input. Use this for: =item Timer and countdown logic =item Animations and indeterminate progress bars (`$widget.tick`) =item Pulling from external streams that aren't tied to user input Multiple callbacks can be registered; they run in registration order.

### method focus

```raku
method focus(
    Selkie::Widget $w
) returns Mu
```

Move focus to a specific widget. The previously-focused widget's `set-focused(False)` is called (if it has one); the new widget's `set-focused(True)` is called. A `ui/focus` event is dispatched to the store so subscribers (e.g. `Selkie::Widget::Border`) can update their appearance. Passing an undefined widget is treated as "focus the first focusable on the active surface" — Selkie maintains the invariant that `$!focused` is attached whenever focusable widgets exist. The only legitimate "focus: nothing" state is a surface with zero focusables, in which case `$!focused` stays undefined.

### method widget-attached

```raku
method widget-attached(
    Selkie::Widget $w,
    $root
) returns Bool
```

True iff walking up `$w`'s parent chain reaches `$root`. Used internally to validate that a saved focus reference (in `%!screen-focus` or `$!pre-modal-focus`) is still attached to the live tree before we try to restore it. O(tree depth); cheap. Public (rather than private with a leading bang) so tests can exercise the logic via the type object — `Selkie::App.widget-attached(...)` works without constructing an App instance (which would require `notcurses_init`). Apps rarely need to call this directly.

### method check-focus-invariant

```raku
method check-focus-invariant() returns Mu
```

Verify that `$!focused` is still attached to the input-owning surface (the active modal, or the active screen). If it's dangling — its container was removed, its screen was destroyed, etc. — re-focus the first focusable on the surface. No-op when focus is already valid, or when nothing was focused to begin with. Called automatically at the top of every event-loop iteration. Exposed as a public method mainly so tests can drive the guard directly without spinning `run` — apps don't normally need to call it.

### method focus-next

```raku
method focus-next() returns Mu
```

Move focus to the next focusable widget in the tree. Wraps around at the end. Bound to `Tab` by default.

### method focus-prev

```raku
method focus-prev() returns Mu
```

Move focus to the previous focusable widget. Wraps around at the beginning. Bound to `Shift-Tab` by default.

### method quit

```raku
method quit() returns Mu
```

Signal the event loop to exit. `run` returns after the current frame completes; the terminal is restored by `shutdown`.

### method run

```raku
method run() returns Mu
```

Start the event loop. Blocks until `quit` is called or an unhandled exception bubbles up. The loop wakes on a 16ms input timeout (up to 60 Hz) and handles: input polling, event dispatch, frame callbacks, store tick, focus action processing, toast tick, and rendering. Idle work is minimized on each dimension: resize polling is throttled to ~12 Hz, the store tick only walks subscriptions when events were processed, and the renderer only composites to the terminal when a widget actually rendered (or the toast just auto-dismissed). A static screen produces near-zero CPU. The loop body is wrapped in a `CATCH` block: any thrown exception triggers an orderly shutdown, prints a backtrace to STDERR, and exits the process with status 1.

### method check-terminal-resize

```raku
method check-terminal-resize() returns Bool
```

Check whether the terminal has been resized and, if so, propagate new dimensions through the widget tree and force a full terminal re-sync. Called every ~83ms from the main loop (via `!maybe-check-terminal-resize`) because notcurses doesn't reliably emit `NCKEY_RESIZE` through the input queue on every platform — macOS in particular. Also called synchronously by `!dispatch-event` when a real `ResizeEvent` arrives, which should not be rate-limited. No-op when dims haven't changed; cheap.

### method maybe-check-terminal-resize

```raku
method maybe-check-terminal-resize() returns Bool
```

Rate-limit wrapper around `!check-terminal-resize`. Called from the main loop every frame, but only lets the underlying check run at most once per ~83ms (~12 Hz). See `!check-terminal-resize` for why we poll at all. Returns True when a dim change was actually detected and the UI re-flowed; False otherwise. Used by the idle ladder to treat a resize as activity.

### method render-frame

```raku
method render-frame(
    Bool :$force = Bool::False
) returns Mu
```

Render any dirty parts of the widget tree and, if anything actually rendered, composite the frame to the terminal via `notcurses_render`. The composite is **gated on whether any widget rendered this frame**. On a static screen — no dirty widgets, no visible toast — the frame is a no-op: we skip the compositor, the terminal diff, and the pty writes that would otherwise run ~60 Hz while idle. The `:force` flag overrides the gate. It's set by the main loop when `Toast.tick` reports that visibility just flipped off: the previous composite still shows the toast, so we need one more render to erase it even though no widget is dirty.

### method shutdown

```raku
method shutdown() returns Mu
```

Shut down notcurses and destroy the active modal and screen manager. Idempotent — safe to call multiple times. Usually you don't call this directly; the event loop's CATCH, the END phaser, or `DESTROY` takes care of it.

### method set-error-log

```raku
method set-error-log(
    Str $path
) returns Mu
```

Swap the active error-log file at runtime. Tears down the current redirection (restoring fd 2 to the original stderr), updates the path, and reinstalls the redirect pointing at the new file. Passing `Str` (the type object) or an empty string disables redirection — fd 2 goes back to wherever it pointed before the first `install-error-log`. Useful for apps whose log location only becomes known after some runtime event. App::Cantina is the canonical consumer: the path is `{cantina-home}/{db-name}/error.log`, and `db-name` is only known after the user selects / creates a profile on the login screen. The app boots with `error-log` unset, then calls `set-error-log` from its post-login handler. A new session banner is written to the new log file on each invocation so interleaved runs stay navigable. No-op (save for the banner) when called with the same path it already has.

