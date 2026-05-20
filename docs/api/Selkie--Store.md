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

Mutation safety
---------------

It's safe for a subscription's callback to call `unsubscribe`, `unsubscribe-widget`, or any cascade thereof (closing a modal, clearing a container, swapping a pane) while a tick is in progress. `unsubscribe` calls made from inside `!check-subscriptions` or `!flush-push-subs` are queued into a pending set; the actual hash deletions are applied after the walk exits, via a `LEAVE` block that runs whether the walk returns normally or unwinds via an exception. During the walk, queued ids are skipped in the dispatch loop, so a sub unsubscribed by an earlier callback in the same tick does **not** fire later in that same tick — matching the observable behaviour callers depended on before the defer mechanism existed.

Re-subscribing the same id during a walk (`unsubscribe('foo')` followed by `subscribe-with-callback('foo', ...)` in the same callback) cancels the queued removal and tears down the old entry cleanly before installing the new one, so the deferred flush never clobbers the new registration.

Mutations from outside a walk — the common case, a handler running in `!process-queue` or app code calling `unsubscribe` directly — take effect immediately as before. The defer mechanism is invisible to that path.

The invariant the walks maintain: `%!subscriptions` and `%!push-subs-by-key` are never mutated while a walk is iterating them. Earlier implementations relied on `:exists` guards plus `.keys.List` snapshots, but neither survived realistic load (App::Cantina character changes cascade ~120 `unsubscribe` calls through one callback firing); the typed eager Array snapshot (`my Str:D @ids = %!subscriptions.keys`) plus the queued-mutation discipline above is what actually holds.

Equality semantics
------------------

Subscription computes are compared against the previous value with a two-stage check: identity (`===`) first, then value equality (`eqv`) if that fails. `eqv` does deep comparison on arrays and hashes, so subscriptions that return the same content in a fresh array instance don't fire spuriously.

Mutable nested data and `:identity-check-only`
----------------------------------------------

Change detection on subscriptions defaults to structural (`eqv`) comparison plus a per-fire snapshot of mutable nested state. That default exists because of a subtle trap with the identity-only check: a subscription on path `a`, plus a caller doing `$store.assoc-in('a', 'b', 'c', :value(42))`. `assoc-in` walks into the live nested Hash and mutates the leaf in place; the Hash at `a` is the same in-memory object before and after the write, so:

  * The subscription's `last-value` still holds a reference to the same Hash.

  * The fresh `get-in('a')` at fire time returns the same reference.

  * An `===` identity check matches → the fire is silently suppressed.

The structural-comparison default sidesteps this. On every fire the framework:

  * Snapshots the value (deep clone of nested Hashes / Arrays; scalar leaves passed through) so subsequent in-place mutations don't compare equal to the captured snapshot.

  * Compares the next value structurally against the snapshot via `eqv`.

```raku
# Watch a mutable nested hash. The default just works — deep
# assoc-in writes under <prefs> are detected even though the prefs
# Hash reference itself is unchanged.
$store.subscribe('prefs-changed', <prefs>, $widget);

# Writes that would be suppressed under identity-only comparison
# now fire correctly:
$store.assoc-in('prefs', 'theme', :value('dark'));   # fires
$store.assoc-in('prefs', 'lang',  :value('en'));     # fires
```

Pass `:identity-check-only` when the watched value is guaranteed to be a fresh allocation per write — a Str, an Int, a Bool, a derived count, a freshly-constructed summary Hash. That path skips the snapshot cost and uses `===`-then-`eqv` as the cheaper fast path.

The flag exists on `subscribe`, `subscribe-path-callback`, `subscribe-computed`, and `subscribe-with-callback`.

**Migration from pre-0.8.0 Selkie**: the old `:deep-equality-check` flag is removed. Drop the flag — the safe behaviour is now the default. Pass `:identity-check-only` at any call site that was previously relying on the identity-only fast path.

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

### sub path-key

```raku
sub path-key(
    @path
) returns Str
```

Canonical string encoding of a path for use as a Hash key in the push-subscription reverse index. We join segments with `\0` (NUL) because it's guaranteed never to appear in realistic path keys — all our keys are user-chosen Str. The decode helper is the inverse. Empty path encodes to the empty string.

### method subscribe

```raku
method subscribe(
    Str:D $id,
    @path,
    Selkie::Widget $widget,
    Bool :$identity-check-only = Bool::False
) returns Mu
```

Subscribe a widget to a state path. When the value at the path changes, the widget is marked dirty on the next tick. The `$id` identifies the subscription for later `unsubscribe` — use a unique name per subscription. Push-based: the store pushes a notification to this subscription only when a write touches the path (exact, ancestor, or descendant — see the push-sub dispatch block at the top of the file). Idle ticks with no writes do zero work per subscription. Initial prime (marking the widget dirty so its first render happens) runs synchronously here. Change detection defaults to structural (`eqv`) comparison — correct for mutable containers (Hash / Array) updated in place by `assoc-in` on a deep child, where the ancestor's reference is unchanged across the write. The historical default was identity- only (`===`), which silently suppressed those writes; the safe behaviour is now opt-out via `:identity-check-only` for paths whose value is guaranteed to be a fresh allocation on each write. See **MUTABLE NESTED DATA** in this module's Pod.

### method subscribe-path-callback

```raku
method subscribe-path-callback(
    Str:D $id,
    @path,
    &callback,
    Selkie::Widget $widget,
    Bool :$identity-check-only = Bool::False
) returns Mu
```

Subscribe to a state path with a callback — fires `&callback($new-value)` on any real change to the path (exact, ancestor write, or descendant write that replaced the subtree). No compute function needed: the path IS the watched expression. Also marks the owning widget dirty so it re-renders after the callback configures it. Use when your widget needs reconfiguration on change (e.g. `set-items` on a list, `set-text` on a label) rather than just re-rendering the same computed output. Equivalent to `subscribe-with-callback` with a trivial compute closure, but without the per-tick closure invocation cost — push-based like `subscribe`. Change detection defaults to structural comparison, mirroring `subscribe`. Pass `:identity-check-only` when the watched path's value is a fresh allocation per write. The callback always receives the live current value; only the change-gate uses the snapshot.

### method subscribe-computed

```raku
method subscribe-computed(
    Str:D $id,
    &compute,
    Selkie::Widget $widget,
    Bool :$identity-check-only = Bool::False
) returns Mu
```

Subscribe a widget to a computed value. `&compute` receives the store each tick and should return the value. The widget is marked dirty when the return value changes. Change detection defaults to **structural** comparison: the result is snapshotted after each fire and the next fire compares against the snapshot via `eqv`. This correctly handles compute functions that return references into mutable nested state — the common case of `$store.get-in('chat', 'messages')` after an `assoc-in` deep- write, where identity-only comparison sees the same Hash reference and silently suppresses the fire. See **MUTABLE NESTED DATA** in this module's Pod. Set `:identity-check-only` when `&compute` is known to return a fresh value per call (a Str, a Bool, a derived count, a freshly- built Hash) — this skips the snapshot cost.

### method subscribe-with-callback

```raku
method subscribe-with-callback(
    Str:D $id,
    &compute,
    &callback,
    Selkie::Widget $widget,
    Bool :$identity-check-only = Bool::False
) returns Mu
```

Like `subscribe-computed`, but also invokes `&callback` with the new value whenever it changes. Use this when your widget needs to be re-configured (e.g. `set-items` on a list, `set-text` on a label), not just re-rendered. Change detection defaults to structural comparison; see `subscribe-computed`. Pass `:identity-check-only` when the compute function is guaranteed to return fresh values. The callback always receives the live (un-snapshotted) compute result.

### method unsubscribe

```raku
method unsubscribe(
    Str:D $id
) returns Mu
```

Remove a subscription by its id. No-op if the id isn't registered. During a subscription walk (`!check-subscriptions` / `!flush-push-subs`), the actual removal is deferred to walk exit; the queued id is skipped in the dispatch loop, so an earlier callback's unsubscribe is observed in the same tick. Outside a walk, removal is immediate as before.

### method unsubscribe-widget

```raku
method unsubscribe-widget(
    Selkie::Widget $widget
) returns Mu
```

Remove every subscription bound to a widget. Called automatically by `Selkie::Container` when a child is removed — you rarely call this yourself.

### method subscription-count

```raku
method subscription-count() returns Int
```

Total number of active subscriptions. Excludes ids that have been queued for deferred removal but not yet flushed (so counts reflect the post-walk state). Primarily useful for tests asserting that destroy / unsubscribe-widget cleanup ran.

### method tick

```raku
method tick() returns Bool
```

Process one tick of the store. Drains the event queue (invoking handlers, applying effects, possibly enqueuing more events — capped at 100 iterations to prevent infinite loops), then walks every subscription and compares its current value against the previous one. The subscription walk is skipped on ticks where the event queue was empty *and* every subscription has already been primed with its initial value. With nothing new in the store, no subscription value can have changed — walking them would be wasted work. Registering a new subscription flips the prime flag so the next tick initializes it regardless of event activity. Called automatically by `Selkie::App.run` each frame. Call explicitly only when you need to force state resolution outside the main loop (e.g. bootstrapping state before `run` starts).

### method flush-push-subs

```raku
method flush-push-subs() returns Mu
```

Drain `@!dirty-paths` and fire every push subscription whose bound path overlaps with any written path — where "overlaps" means either path is a prefix of the other (ancestor / descendant / exact). Dedupe: a sub only fires once per flush even if multiple writes match it. After dispatching, the dirty-path set is cleared. Firing still respects value-change semantics: `!values-equal` gates whether `&callback` / `mark-dirty` actually runs, so no-op writes don't produce spurious fires.

### method values-equal

```raku
method values-equal(
    $a,
    $b,
    Bool :$deep
) returns Bool
```

Compare two subscription values for equality. The `:deep` flag skips the `===` identity shortcut and forces a structural `eqv` compare — necessary for subscriptions over mutable nested data where the in-place mutation leaves the container's identity unchanged but its contents differ. Set by default on all subscribe paths; opt out via `:identity-check-only` on the `subscribe*` methods when the watched value is a fresh allocation per write.

### method snapshot-value

```raku
method snapshot-value(
    $v
) returns Mu
```

Recursive deep clone for subscription change-detection. Returns a fresh Hash / Array at every container level so subsequent in-place mutations of the live store value can't alias back to the captured snapshot. Scalar leaves (Str, Int, Num, Bool, type objects) are returned as-is — they're immutable, so sharing the reference is safe. Used on the structural-comparison path (the default); the `:identity-check-only` fast path skips this work.

### method shutting-down

```raku
method shutting-down() returns Bool
```

True once `drain-async` has flipped the store into shutdown mode. Callers (typically the `async` fx) can poll this to short-circuit dispatches that would race against a tearing-down App.

### method drain-async

```raku
method drain-async(
    :$timeout = 5
) returns Mu
```

Wait for every in-flight async-effect worker to complete (or for the timeout to elapse), flip the store into shutdown mode so any further `async` dispatches no-op, and clear the tracking list. Called from `Selkie::App.shutdown` before notcurses is torn down so completing workers can't dispatch into handlers whose native deps are gone. Idempotent — a second call is a fast no-op (the list is empty and `$!shutting-down` is already True).

