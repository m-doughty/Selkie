NAME
====

Selkie::Store - Reactive state store with dispatch, effects, and subscriptions

SYNOPSIS
========

```raku
my $store = $app.store;

# Register a handler that returns effects (never mutate state directly)
$store.register-handler('counter/inc', -> $st, %ev {
    my $current = $st.get-in('count') // 0;
    (db => { count => $current + 1 },);
});

# Subscribe a widget to a path — marks it dirty when the value changes
$store.subscribe('my-counter', ['count'], $widget);

# Or: subscribe with a callback that does something on change
$store.subscribe-with-callback(
    'counter-text',
    -> $s { "Count: {$s.get-in('count') // 0}" },
    -> $text { $label.set-text($text) },
    $label,
);

# Fire an event from anywhere — it's queued and processed on the next tick
$store.dispatch('counter/inc');
```

DESCRIPTION
===========

Selkie's store is inspired by [re-frame](https://github.com/day8/re-frame) — one centralized state atom with a one-way data flow:

    user action → dispatch event
    event       → handlers return effects
    effects     → mutate state (via registered effect handlers)
    state       → subscriptions notify widgets
    widgets     → re-render

Handlers are **pure functions**. Given a store and event payload, they return a list of effects. Effects are where side effects live — built-in ones (`db`, `dispatch`, `async`) cover most needs; you can register your own with `register-fx`.

Why?
----

Why go through all this ceremony versus just mutating state? Because:

  * State changes are **auditable** — every mutation is a named event with a payload

  * Handlers are **testable** — no notcurses, no widgets, just pure functions

  * Time-travel / logging / middleware become possible without changing app code

  * Subscriptions **derive** UI from state — you don't manually sync widgets with state

You don't have to use the store. For small apps, widget Supplies taped directly to side-effecting code works fine. The store shines when shared state grows — multiple widgets reading the same data, actions that cascade, async workflows with multiple steps.

EXAMPLES
========

A counter
---------

Two handlers, one subscription:

```raku
$store.register-handler('counter/inc', -> $st, %ev {
    (db => { count => ($st.get-in('count') // 0) + 1 },);
});
$store.register-handler('counter/reset', -> $st, %ev {
    (db => { count => 0 },);
});

$store.subscribe-with-callback(
    'counter-display',
    -> $s { "Count: {$s.get-in('count') // 0}" },
    -> $text { $display.set-text($text) },
    $display,
);

$inc-button.on-press.tap:   -> $ { $store.dispatch('counter/inc') };
$reset-button.on-press.tap: -> $ { $store.dispatch('counter/reset') };
```

Chaining events
---------------

The `dispatch` effect lets a handler trigger another event. Use it when one action implies another:

```raku
$store.register-handler('user/logged-in', -> $st, %ev {
    (
        db       => { user => %ev<user> },
        dispatch => { event => 'inbox/fetch' },
    );
});
```

Async work
----------

The `async` effect runs work on a worker thread, then dispatches a follow-up event with the result (or error). The handler itself returns immediately — the store doesn't block:

```raku
$store.register-handler('inbox/fetch', -> $st, %ev {
    (async => {
        work       => -> { fetch-messages-from-api() },
        on-success => 'inbox/loaded',
        on-failure => 'inbox/load-failed',
    },);
});

$store.register-handler('inbox/loaded', -> $st, %ev {
    (db => { inbox => %ev<result> },);
});

$store.register-handler('inbox/load-failed', -> $st, %ev {
    (db => { error => %ev<error> },);
});
```

Computed subscriptions
----------------------

`subscribe-computed` watches a derived value. Fires only when the computed result changes, not every time the underlying state does:

```raku
$store.subscribe-computed(
    'unread-count',
    -> $s { $s.get-in('inbox').grep(*<read> == False).elems },
    $badge-widget,
);
```

Debugging
---------

Turn on logging during development to see the data flow:

```raku
$app.store.enable-debug;           # logs to $*ERR
# or to a file:
$app.store.enable-debug(log => open('store.log', :w));
```

Output:

    [1776073200.123] dispatch task/add text=Buy milk
    [1776073200.123]   → db: {tasks => [...], next-id => 5}
    [1776073200.124]   sub[task-list] fired: [...]

EFFECTS
=======

Handlers return effects rather than mutating state directly. Each effect is a `Pair` of `name =` params>, or an `Associative` with multiple pairs.

Built-in effects
----------------

  * `db => { ... } ` — deep-merge into the state tree. Nested hashes are merged recursively; non-hash values are set directly. This is the workhorse effect — most handlers return one.

  * `dispatch => { event => 'name', ...payload } ` — enqueue another event. Processed in the same tick.

  * `async => { work => &fn, on-success => 'name', on-failure => 'name' } ` — run `&fn` on a worker thread. On return, dispatch `on-success` with a `result` payload. On throw, dispatch `on-failure` with an `error` payload.

Custom effects
--------------

Register your own with `register-fx` for repeated side effects that you want named:

```raku
$store.register-fx('log', -> $store, %params {
    my $line = %params<line>;
    $log-file.say("[{DateTime.now}] $line");
});

# Then use from any handler:
$store.register-handler('task/deleted', -> $st, %ev {
    (
        db  => { tasks => %ev<remaining> },
        log => { line => "deleted task {%ev<id>}" },
    );
});
```

SUBSCRIPTIONS
=============

Three kinds, chosen by what you want to do on change:

  * `subscribe($id, @path, $widget)` — watch a state path. The widget is marked dirty when the value at that path changes. Simplest form.

  * `subscribe-computed($id, &compute, $widget)` — watch a derived value. Runs `&compute` every tick; marks the widget dirty when the return value changes.

  * `subscribe-with-callback($id, &compute, &callback, $widget)` — same as computed, but also invokes `&callback` with the new value. Use when the widget needs to be re-configured (e.g. `set-items` on a list), not just re-rendered.

All three use `$id` as a unique key — re-subscribing with the same id overwrites the previous subscription. `unsubscribe($id)` removes one by key; `unsubscribe-widget($w)` removes every subscription bound to a widget (used during widget destruction).

Equality semantics
------------------

Subscription computes are compared against the previous value with a two-stage check: identity (`===`) first, then value equality (`eqv`) if that fails. `eqv` does deep comparison on arrays and hashes, so subscriptions that return the same content in a fresh array instance don't fire spuriously.

SEE ALSO
========

  * [Selkie::Widget](Selkie--Widget.md) — widgets receive subscriptions and dispatch events

  * [Selkie::App](Selkie--App.md) — registers `ui/focus`, `ui/focus-next`, `ui/focus-prev` handlers by default

### method enable-debug

```raku
method enable-debug(
    IO::Handle :$log = Code.new,
    Bool :$dispatches = Bool::True,
    Bool :$effects = Bool::True,
    Bool :$subscriptions = Bool::True
) returns Mu
```

Enable logging of dispatches, effects, and subscription fires. Output lines go to `$log` (defaults to `$*ERR`). Pass `:!dispatches`, `:!effects`, or `:!subscriptions` to silence a specific category. Overhead when disabled is a single Bool check per hook.

### method disable-debug

```raku
method disable-debug() returns Mu
```

Turn off debug logging.

### method db

```raku
method db() returns Hash
```

Access the raw state Hash. Read-only in practice — mutate via dispatch.

### method get-in

```raku
method get-in(
    *@path
) returns Mu
```

Deep-read a value at a path. Returns `Nil` if any step in the path is missing or not a Hash. Useful in handlers and subscription computes: my $name = $store.get-in('app', 'user', 'name'); # may be Nil

### method assoc-in

```raku
method assoc-in(
    *@path,
    :$value!
) returns Mu
```

Deep-write a value at a path, auto-creating intermediate Hashes as needed. **Prefer dispatch-and-handle over calling this directly from app code** — direct mutations bypass the auditability that the dispatch pattern gives you. This is public for legitimate framework use (e.g. App's internal focus-action flag). $store.assoc-in('app', 'user', 'name', value => 'Alice');

### method dispatch

```raku
method dispatch(
    Str:D $event,
    *%payload
) returns Mu
```

Enqueue an event for processing on the next tick. The event name is routed to every handler registered for that name; their returned effects are applied in order.

### method register-handler

```raku
method register-handler(
    Str:D $event,
    &handler
) returns Mu
```

Register a handler for an event name. Multiple handlers per event are supported — all are called and their effects merged. The handler signature is `sub ($store, %payload --` @effects)>. Return a single effect Pair, a list of Pairs, or a Hash of effects. Return an empty list or `()` to apply no effects.

### method register-fx

```raku
method register-fx(
    Str:D $fx-name,
    &handler
) returns Mu
```

Register a custom effect handler. The handler receives the store and a Hash of params, and performs side effects. See EFFECTS above for the built-in ones and an example of registering your own.

### method subscribe

```raku
method subscribe(
    Str:D $id,
    @path,
    Selkie::Widget $widget
) returns Mu
```

Subscribe a widget to a state path. When the value at the path changes, the widget is marked dirty on the next tick. The `$id` identifies the subscription for later `unsubscribe` — use a unique name per subscription.

### method subscribe-computed

```raku
method subscribe-computed(
    Str:D $id,
    &compute,
    Selkie::Widget $widget
) returns Mu
```

Subscribe a widget to a computed value. `&compute` receives the store each tick and should return the value. The widget is marked dirty when the return value changes (compared with `eqv` / identity).

### method subscribe-with-callback

```raku
method subscribe-with-callback(
    Str:D $id,
    &compute,
    &callback,
    Selkie::Widget $widget
) returns Mu
```

Like `subscribe-computed`, but also invokes `&callback` with the new value whenever it changes. Use this when your widget needs to be re-configured (e.g. `set-items` on a list, `set-text` on a label), not just re-rendered.

### method unsubscribe

```raku
method unsubscribe(
    Str:D $id
) returns Mu
```

Remove a subscription by its id. No-op if the id isn't registered.

### method unsubscribe-widget

```raku
method unsubscribe-widget(
    Selkie::Widget $widget
) returns Mu
```

Remove every subscription bound to a widget. Called automatically by `Selkie::Container` when a child is removed — you rarely call this yourself.

### method tick

```raku
method tick() returns Mu
```

Process one tick of the store. Drains the event queue (invoking handlers, applying effects, possibly enqueuing more events — capped at 100 iterations to prevent infinite loops), then walks every subscription and compares its current value against the previous one. Called automatically by `Selkie::App.run` each frame. Call explicitly only when you need to force state resolution outside the main loop (e.g. bootstrapping state before `run` starts).

