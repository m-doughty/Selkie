=begin pod

=head1 NAME

Selkie::Store - Reactive state store with dispatch, effects, and subscriptions

=head1 SYNOPSIS

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

Selkie's store is inspired by L<re-frame|https://github.com/day8/re-frame> —
one centralized state atom with a one-way data flow:

    user action → dispatch event
    event       → handlers return effects
    effects     → mutate state (via registered effect handlers)
    state       → subscriptions notify widgets
    widgets     → re-render

Handlers are B<pure functions>. Given a store and event payload, they
return a list of effects. Effects are where side effects live — built-in
ones (C<db>, C<dispatch>, C<async>) cover most needs; you can register
your own with C<register-fx>.

=head2 Why?

Why go through all this ceremony versus just mutating state? Because:

=item State changes are B<auditable> — every mutation is a named event with a payload
=item Handlers are B<testable> — no notcurses, no widgets, just pure functions
=item Time-travel / logging / middleware become possible without changing app code
=item Subscriptions B<derive> UI from state — you don't manually sync widgets with state

You don't have to use the store. For small apps, widget Supplies taped
directly to side-effecting code works fine. The store shines when shared
state grows — multiple widgets reading the same data, actions that
cascade, async workflows with multiple steps.

=head1 EXAMPLES

=head2 A counter

Two handlers, one subscription:

=begin code :lang<raku>

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

=end code

=head2 Chaining events

The C<dispatch> effect lets a handler trigger another event. Use it when
one action implies another:

=begin code :lang<raku>

$store.register-handler('user/logged-in', -> $st, %ev {
    (
        db       => { user => %ev<user> },
        dispatch => { event => 'inbox/fetch' },
    );
});

=end code

=head2 Async work

The C<async> effect runs work on a worker thread, then dispatches a
follow-up event with the result (or error). The handler itself returns
immediately — the store doesn't block:

=begin code :lang<raku>

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

=end code

=head2 Computed subscriptions

C<subscribe-computed> watches a derived value. Fires only when the
computed result changes, not every time the underlying state does:

=begin code :lang<raku>

$store.subscribe-computed(
    'unread-count',
    -> $s { $s.get-in('inbox').grep(*<read> == False).elems },
    $badge-widget,
);

=end code

=head2 Debugging

Turn on logging during development to see the data flow:

=begin code :lang<raku>

$app.store.enable-debug;           # logs to $*ERR
# or to a file:
$app.store.enable-debug(log => open('store.log', :w));

=end code

Output:

    [1776073200.123] dispatch task/add text=Buy milk
    [1776073200.123]   → db: {tasks => [...], next-id => 5}
    [1776073200.124]   sub[task-list] fired: [...]

=head1 EFFECTS

Handlers return effects rather than mutating state directly. Each effect
is a C<Pair> of C<name => params>, or an C<Associative> with multiple
pairs.

=head2 Built-in effects

=item C<< db => { ... } >> — deep-merge into the state tree. Nested hashes are merged recursively; non-hash values are set directly. This is the workhorse effect — most handlers return one.

=item C<< dispatch => { event => 'name', ...payload } >> — enqueue another event. Processed in the same tick.

=item C<< async => { work => &fn, on-success => 'name', on-failure => 'name' } >> — run C<&fn> on a worker thread. On return, dispatch C<on-success> with a C<result> payload. On throw, dispatch C<on-failure> with an C<error> payload.

=head2 Custom effects

Register your own with C<register-fx> for repeated side effects that
you want named:

=begin code :lang<raku>

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

=end code

=head1 SUBSCRIPTIONS

Three kinds, chosen by what you want to do on change:

=item C<subscribe($id, @path, $widget)> — watch a state path. The widget is marked dirty when the value at that path changes. Simplest form.

=item C<subscribe-computed($id, &compute, $widget)> — watch a derived value. Runs C<&compute> every tick; marks the widget dirty when the return value changes.

=item C<subscribe-with-callback($id, &compute, &callback, $widget)> — same as computed, but also invokes C<&callback> with the new value. Use when the widget needs to be re-configured (e.g. C<set-items> on a list), not just re-rendered.

All three use C<$id> as a unique key — re-subscribing with the same id
overwrites the previous subscription. C<unsubscribe($id)> removes one
by key; C<unsubscribe-widget($w)> removes every subscription bound to
a widget (used during widget destruction).

=head2 Mutation safety

It's safe for a subscription's callback to call C<unsubscribe>,
C<unsubscribe-widget>, or any cascade thereof (closing a modal,
clearing a container, swapping a pane) while a tick is in progress.
C<unsubscribe> calls made from inside C<!check-subscriptions> or
C<!flush-push-subs> are queued into a pending set; the actual hash
deletions are applied after the walk exits, via a C<LEAVE> block
that runs whether the walk returns normally or unwinds via an
exception. During the walk, queued ids are skipped in the dispatch
loop, so a sub unsubscribed by an earlier callback in the same tick
does B<not> fire later in that same tick — matching the observable
behaviour callers depended on before the defer mechanism existed.

Re-subscribing the same id during a walk (C<unsubscribe('foo')>
followed by C<subscribe-with-callback('foo', ...)> in the same
callback) cancels the queued removal and tears down the old entry
cleanly before installing the new one, so the deferred flush never
clobbers the new registration.

Mutations from outside a walk — the common case, a handler running
in C<!process-queue> or app code calling C<unsubscribe> directly —
take effect immediately as before. The defer mechanism is invisible
to that path.

The invariant the walks maintain: C<%!subscriptions> and
C<%!push-subs-by-key> are never mutated while a walk is iterating
them. Earlier implementations relied on C<:exists> guards plus
C<.keys.List> snapshots, but neither survived realistic load
(App::Cantina character changes cascade ~120 C<unsubscribe> calls
through one callback firing); the typed eager Array snapshot
(C<my Str:D @ids = %!subscriptions.keys>) plus the queued-mutation
discipline above is what actually holds.

=head2 Equality semantics

Subscription computes are compared against the previous value with a
two-stage check: identity (C<===>) first, then value equality (C<eqv>)
if that fails. C<eqv> does deep comparison on arrays and hashes, so
subscriptions that return the same content in a fresh array instance
don't fire spuriously.

=head2 Mutable nested data and C<:identity-check-only>

Change detection on subscriptions defaults to structural (C<eqv>)
comparison plus a per-fire snapshot of mutable nested state. That
default exists because of a subtle trap with the identity-only check:
a subscription on path C<a>, plus a caller doing
C<$store.assoc-in('a', 'b', 'c', :value(42))>. C<assoc-in> walks into
the live nested Hash and mutates the leaf in place; the Hash at C<a>
is the same in-memory object before and after the write, so:

=item The subscription's C<last-value> still holds a reference to the same Hash.
=item The fresh C<get-in('a')> at fire time returns the same reference.
=item An C<===> identity check matches → the fire is silently suppressed.

The structural-comparison default sidesteps this. On every fire the
framework:

=item Snapshots the value (deep clone of nested Hashes / Arrays; scalar leaves passed through) so subsequent in-place mutations don't compare equal to the captured snapshot.
=item Compares the next value structurally against the snapshot via C<eqv>.

=begin code :lang<raku>

# Watch a mutable nested hash. The default just works — deep
# assoc-in writes under <prefs> are detected even though the prefs
# Hash reference itself is unchanged.
$store.subscribe('prefs-changed', <prefs>, $widget);

# Writes that would be suppressed under identity-only comparison
# now fire correctly:
$store.assoc-in('prefs', 'theme', :value('dark'));   # fires
$store.assoc-in('prefs', 'lang',  :value('en'));     # fires

=end code

Pass C<:identity-check-only> when the watched value is guaranteed to
be a fresh allocation per write — a Str, an Int, a Bool, a derived
count, a freshly-constructed summary Hash. That path skips the
snapshot cost and uses C<===>-then-C<eqv> as the cheaper fast path.

The flag exists on C<subscribe>, C<subscribe-path-callback>,
C<subscribe-computed>, and C<subscribe-with-callback>.

B<Migration from pre-0.8.0 Selkie>: the old C<:deep-equality-check>
flag is removed. Drop the flag — the safe behaviour is now the
default. Pass C<:identity-check-only> at any call site that was
previously relying on the identity-only fast path.

=head1 SEE ALSO

=item L<Selkie::Widget> — widgets receive subscriptions and dispatch events
=item L<Selkie::App> — registers C<ui/focus>, C<ui/focus-next>, C<ui/focus-prev> handlers by default

=end pod

unit class Selkie::Store;

use Selkie::Widget;

has %!db;
has @!event-queue;
has %!handlers;          # event-name → Array[&handler]
has %!fx-handlers;       # fx-name → &handler
has %!subscriptions;     # sub-id → Hash{ path|compute, last-value, widget }
has Bool $!subs-primed = False;

# --- Push-based path subscription infrastructure -------------------
#
# Path subscriptions (`subscribe` + `subscribe-path-callback`) don't
# get walked every tick. Instead, every mutation to the store (via
# `assoc-in` or a `db` effect's deep-merge) records the affected
# paths in `@!dirty-paths`. On tick, `!flush-push-subs` drains that
# set and fires the matching subscribers — those whose path is a
# prefix of a written path (ancestor notification: "something in my
# subtree changed") OR whose path has a written path as a prefix
# (descendant notification: "my subtree was replaced / written
# over"). Exact-match is the prefix-equal edge of either direction.
#
# After firing, each matched subscriber's current value is compared
# to its last-known value; the callback + widget-dirty only actually
# fire when the value differs — matching the pull-based `eqv` /
# identity semantics so a no-op write doesn't spuriously fire subs.
#
# `computed` and `callback` subscriptions still pay the per-tick
# walk because their compute closures can depend on arbitrary state
# we can't cheaply index. The set of push-participating types is
# fixed: 'path', 'path-callback'. See `!check-subscriptions` for
# the pull split.
has @!dirty-paths;        # List of path Lists written since last flush
has %!push-subs-by-key;   # path-key → Array[sub-id]

# Walks (!check-subscriptions, !flush-push-subs) set this True
# while iterating. Any `unsubscribe` called during that window is
# captured in $!pending-unsubscribes and applied after the walk
# exits via the LEAVE block — never mid-iteration. See "Mutation
# safety" in the Pod above for the contract.
has Bool    $!in-subscription-walk = False;
has SetHash $!pending-unsubscribes .= new;

has IO::Handle $!debug-log;
has Bool $!debug-dispatches    = False;
has Bool $!debug-effects       = False;
has Bool $!debug-subscriptions = False;

# Async-effect tracking: every Promise produced by register-fx('async')
# is registered here so App.shutdown can drain in-flight work before
# tearing down notcurses. Without this the worker thread can complete
# after notcurses_stop and dispatch into handlers whose native deps
# are gone (SIGBUS on plane access, NPE on Nil $!nc).
has @!async-effects;
has Lock $!async-lock .= new;
has Bool $!shutting-down = False;

#|( Enable logging of dispatches, effects, and subscription fires. Output
    lines go to C<$log> (defaults to C<$*ERR>). Pass
    C<:!dispatches>, C<:!effects>, or C<:!subscriptions> to silence a
    specific category. Overhead when disabled is a single Bool check per
    hook. )
method enable-debug(
    IO::Handle :$log       = $*ERR,
    Bool       :$dispatches    = True,
    Bool       :$effects       = True,
    Bool       :$subscriptions = True,
) {
    $!debug-log           = $log;
    $!debug-dispatches    = $dispatches;
    $!debug-effects       = $effects;
    $!debug-subscriptions = $subscriptions;
}

#| Turn off debug logging.
method disable-debug() {
    $!debug-log = IO::Handle;
    $!debug-dispatches = $!debug-effects = $!debug-subscriptions = False;
}

method !debug-log-enabled(--> Bool) { $!debug-log.defined }

method !log-line(Str:D $line) {
    return without $!debug-log;
    my $ts = now.Rat.fmt('%.3f');
    $!debug-log.say("[$ts] $line");
}

method !fmt-value($v --> Str) {
    return '(undef)' without $v;
    try {
        my $s = $v.gist;
        $s = $s.substr(0, 80) ~ '…' if $s.chars > 80;
        return $s;
    }
    '<unprintable>';
}

submethod TWEAK() {
    self.register-fx('db', -> $store, %params {
        $store!deep-merge(%params);
    });

    self.register-fx('dispatch', -> $store, %params {
        $store.dispatch(%params<event>, |%params.grep(*.key ne 'event').Hash);
    });

    self.register-fx('async', -> $store, %params {
        my &work       = %params<work>     // die "async fx requires :work";
        my $on-success = %params<on-success>;
        my $on-failure = %params<on-failure>;
        # Only the SCHEDULING decision checks shutting-down: once
        # drain-async is in progress, no new workers get spawned.
        # In-flight workers keep running so their on-success /
        # on-failure dispatches can complete while the store is still
        # alive (the test "drain waits, then delivers on-success"
        # depends on this). Stale dispatches arriving after the App's
        # run loop has fully exited are harmless — the event queue
        # just isn't drained again. No `return` from pointy blocks
        # — they aren't Routines (memory: raku_return_in_closures).
        unless $store.shutting-down {
            my $p = start {
                CATCH {
                    default {
                        my $msg = .message;
                        my $bt  = .?backtrace.?full.?Str // '';
                        $store!report-async-failure($msg, $bt);
                        if $on-failure {
                            $store.dispatch($on-failure,
                                error     => $msg,
                                exception => $_,
                                backtrace => $bt,
                            );
                        }
                    }
                }
                my $result = work();
                if $on-success {
                    $store.dispatch($on-success, result => $result);
                }
            };
            $store!track-async-effect($p);
        }
    });

    # Default handler for handler-exception events: log to the store's
    # log so apps don't have to register one to get diagnostics. Apps
    # can register additional handlers via `register-handler` to display
    # toasts / modals / send telemetry.
    self.register-handler('__effect-error', -> $store, %payload {
        $store!log-line(
            "[effect-error] {%payload<effect-name>}: {%payload<error>}\n"
          ~ (%payload<backtrace> // '')
        );
        ();
    });
}

# --- State access ---

#| Access the raw state Hash. Read-only in practice — mutate via dispatch.
method db(--> Hash) { %!db }

#|( Deep-read a value at a path. Returns C<Nil> if any step in the path
    is missing or not a Hash. Useful in handlers and subscription
    computes:

        my $name = $store.get-in('app', 'user', 'name');   # may be Nil
    )
method get-in(*@path) {
    my $current = %!db;
    for @path -> $key {
        return Nil unless $current ~~ Associative;
        return Nil unless $current{$key}:exists;
        $current = $current{$key};
    }
    $current<>;
}

#|( Deep-write a value at a path, auto-creating intermediate Hashes as
    needed. B<Prefer dispatch-and-handle over calling this directly from
    app code> — direct mutations bypass the auditability that the
    dispatch pattern gives you. This is public for legitimate framework
    use (e.g. App's internal focus-action flag).

        $store.assoc-in('app', 'user', 'name', value => 'Alice');
    )
method assoc-in(*@path, :$value!) {
    die "Path must not be empty" unless @path;
    my $target = %!db;
    for @path[0 ..^ @path.end] -> $key {
        $target{$key} = {} unless $target{$key} ~~ Associative;
        $target = $target{$key};
    }
    $target{@path[*-1]} = $value;
    self!mark-path-dirty(@path.List);
}

# --- Events ---

#|( Enqueue an event for processing on the next tick. The event name is
    routed to every handler registered for that name; their returned
    effects are applied in order. )
method dispatch(Str:D $event, *%payload) {
    @!event-queue.push({ :$event, :%payload });
}

#|( Register a handler for an event name. Multiple handlers per event
    are supported — all are called and their effects merged.

    The handler signature is C<sub ($store, %payload --> @effects)>.
    Return a single effect Pair, a list of Pairs, or a Hash of effects.
    Return an empty list or C<()> to apply no effects. )
method register-handler(Str:D $event, &handler) {
    %!handlers{$event} = [] unless %!handlers{$event}:exists;
    %!handlers{$event}.push(&handler);
}

# --- Effects ---

#|( Register a custom effect handler. The handler receives the store and
    a Hash of params, and performs side effects. See L<EFFECTS> above
    for the built-in ones and an example of registering your own. )
method register-fx(Str:D $fx-name, &handler) {
    %!fx-handlers{$fx-name} = &handler;
}

# --- Subscriptions ---

my constant $UNSET = class { method WHICH() { 'UNSET' } }.new;

#|( Canonical string encoding of a path for use as a Hash key in the
    push-subscription reverse index. We join segments with C<\0>
    (NUL) because it's guaranteed never to appear in realistic path
    keys — all our keys are user-chosen Str. The decode helper is
    the inverse. Empty path encodes to the empty string. )
our sub path-key(@path --> Str) {
    @path.map(*.Str).join("\0");
}
our sub key-path(Str $key --> List) {
    return ().List unless $key.chars;
    $key.split("\0").List;
}

#|( Subscribe a widget to a state path. When the value at the path
    changes, the widget is marked dirty on the next tick. The C<$id>
    identifies the subscription for later C<unsubscribe> — use a unique
    name per subscription.

    Push-based: the store pushes a notification to this subscription
    only when a write touches the path (exact, ancestor, or descendant —
    see the push-sub dispatch block at the top of the file). Idle
    ticks with no writes do zero work per subscription. Initial prime
    (marking the widget dirty so its first render happens) runs
    synchronously here.

    Change detection defaults to structural (C<eqv>) comparison —
    correct for mutable containers (Hash / Array) updated in place by
    C<assoc-in> on a deep child, where the ancestor's reference is
    unchanged across the write. The historical default was identity-
    only (C<===>), which silently suppressed those writes; the safe
    behaviour is now opt-out via C<:identity-check-only> for paths
    whose value is guaranteed to be a fresh allocation on each write.
    See B<MUTABLE NESTED DATA> in this module's Pod. )
method subscribe(Str:D $id, @path, Selkie::Widget $widget,
                 Bool :$identity-check-only = False) {
    # Re-subscribing an id that's queued for deferred removal: tear
    # down the old entry cleanly *now* and drop the queue marker, so
    # the end-of-walk flush doesn't clobber the new registration.
    if $!pending-unsubscribes{$id} {
        self!do-unsubscribe($id);
        $!pending-unsubscribes.unset($id);
    }
    my $deep = !$identity-check-only;
    %!subscriptions{$id} = {
        type       => 'path',
        path       => @path.List,
        last-value => $UNSET,
        widget     => $widget,
        deep       => $deep,
    };
    self!index-push-sub($id, @path);
    # Prime synchronously: mark the widget dirty so it renders with
    # its initial bound value without needing a synthetic event.
    $widget.mark-dirty if $widget.defined;
    # Record the initial value so the first actual write only fires
    # if it represents a real change. On the structural-comparison
    # path snapshot the value so subsequent in-place mutations don't
    # compare equal to a still-live reference.
    my $current = self.get-in(|@path);
    %!subscriptions{$id}<last-value> =
        $deep ?? self!snapshot-value($current) !! $current;
}

#|( Subscribe to a state path with a callback — fires C<&callback($new-value)>
    on any real change to the path (exact, ancestor write, or descendant
    write that replaced the subtree). No compute function needed: the
    path IS the watched expression. Also marks the owning widget dirty
    so it re-renders after the callback configures it.

    Use when your widget needs reconfiguration on change (e.g. C<set-items>
    on a list, C<set-text> on a label) rather than just re-rendering the
    same computed output. Equivalent to C<subscribe-with-callback> with
    a trivial compute closure, but without the per-tick closure
    invocation cost — push-based like C<subscribe>.

    Change detection defaults to structural comparison, mirroring
    C<subscribe>. Pass C<:identity-check-only> when the watched path's
    value is a fresh allocation per write. The callback always
    receives the live current value; only the change-gate uses the
    snapshot. )
method subscribe-path-callback(Str:D $id, @path, &callback, Selkie::Widget $widget,
                               Bool :$identity-check-only = False) {
    if $!pending-unsubscribes{$id} {
        self!do-unsubscribe($id);
        $!pending-unsubscribes.unset($id);
    }
    my $deep = !$identity-check-only;
    %!subscriptions{$id} = {
        type       => 'path-callback',
        path       => @path.List,
        callback   => &callback,
        last-value => $UNSET,
        widget     => $widget,
        deep       => $deep,
    };
    self!index-push-sub($id, @path);
    # Prime: fire the callback with the current value so the widget
    # gets configured immediately. Mark dirty too — callback may or
    # may not trigger a render indirectly, but the prime render is
    # always desired.
    my $current = self.get-in(|@path);
    %!subscriptions{$id}<last-value> =
        $deep ?? self!snapshot-value($current) !! $current;
    $widget.mark-dirty if $widget.defined;
    &callback($current);
}

method !index-push-sub(Str:D $id, @path) {
    my $key = path-key(@path);
    %!push-subs-by-key{$key} = [] unless %!push-subs-by-key{$key}:exists;
    %!push-subs-by-key{$key}.push: $id;
}

method !unindex-push-sub(Str:D $id, @path) {
    my $key = path-key(@path);
    return unless %!push-subs-by-key{$key}:exists;
    %!push-subs-by-key{$key} = %!push-subs-by-key{$key}.grep(* ne $id).Array;
    %!push-subs-by-key{$key}:delete unless %!push-subs-by-key{$key}.elems;
}

#|( Subscribe a widget to a computed value. C<&compute> receives the
    store each tick and should return the value. The widget is marked
    dirty when the return value changes.

    Change detection defaults to B<structural> comparison: the result
    is snapshotted after each fire and the next fire compares against
    the snapshot via C<eqv>. This correctly handles compute functions
    that return references into mutable nested state — the common case
    of C<$store.get-in('chat', 'messages')> after an C<assoc-in> deep-
    write, where identity-only comparison sees the same Hash reference
    and silently suppresses the fire. See B<MUTABLE NESTED DATA> in
    this module's Pod.

    Set C<:identity-check-only> when C<&compute> is known to return a
    fresh value per call (a Str, a Bool, a derived count, a freshly-
    built Hash) — this skips the snapshot cost. )
method subscribe-computed(Str:D $id, &compute, Selkie::Widget $widget,
                          Bool :$identity-check-only = False) {
    if $!pending-unsubscribes{$id} {
        self!do-unsubscribe($id);
        $!pending-unsubscribes.unset($id);
    }
    %!subscriptions{$id} = {
        type       => 'computed',
        compute    => &compute,
        last-value => $UNSET,
        widget     => $widget,
        deep       => !$identity-check-only,
    };
    $!subs-primed = False;
}

#|( Like C<subscribe-computed>, but also invokes C<&callback> with the
    new value whenever it changes. Use this when your widget needs to
    be re-configured (e.g. C<set-items> on a list, C<set-text> on a
    label), not just re-rendered.

    Change detection defaults to structural comparison; see
    C<subscribe-computed>. Pass C<:identity-check-only> when the
    compute function is guaranteed to return fresh values. The
    callback always receives the live (un-snapshotted) compute
    result. )
method subscribe-with-callback(Str:D $id, &compute, &callback, Selkie::Widget $widget,
                               Bool :$identity-check-only = False) {
    if $!pending-unsubscribes{$id} {
        self!do-unsubscribe($id);
        $!pending-unsubscribes.unset($id);
    }
    %!subscriptions{$id} = {
        type       => 'callback',
        compute    => &compute,
        callback   => &callback,
        last-value => $UNSET,
        widget     => $widget,
        deep       => !$identity-check-only,
    };
    $!subs-primed = False;
}

#|( Remove a subscription by its id. No-op if the id isn't registered.

    During a subscription walk (C<!check-subscriptions> /
    C<!flush-push-subs>), the actual removal is deferred to walk
    exit; the queued id is skipped in the dispatch loop, so an
    earlier callback's unsubscribe is observed in the same tick.
    Outside a walk, removal is immediate as before. )
method unsubscribe(Str:D $id) {
    if $!in-subscription-walk {
        $!pending-unsubscribes.set($id);
        return;
    }
    self!do-unsubscribe($id);
}

# Actual hash mutation — caller has already established that this
# is safe (either outside a walk, or via !flush-pending-unsubscribes
# at walk exit).
method !do-unsubscribe(Str:D $id) {
    my %sub = %!subscriptions{$id} // return;
    if (%sub<type> // '') eq any('path', 'path-callback') {
        self!unindex-push-sub($id, %sub<path>);
    }
    %!subscriptions{$id}:delete;
}

# Drain the pending-unsubscribe set, applying each deferred removal.
# Called from the LEAVE block of every walk wrapper.
method !flush-pending-unsubscribes() {
    return unless $!pending-unsubscribes.elems;
    my @to-flush = $!pending-unsubscribes.keys.List;
    $!pending-unsubscribes = SetHash.new;
    self!do-unsubscribe($_) for @to-flush;
}

#|( Remove every subscription bound to a widget. Called automatically by
    C<Selkie::Container> when a child is removed — you rarely call this
    yourself. )
method unsubscribe-widget(Selkie::Widget $widget) {
    my @to-remove = %!subscriptions.grep(*.value<widget> === $widget).map(*.key);
    self.unsubscribe($_) for @to-remove;
}

#| Total number of active subscriptions. Excludes ids that have been
#| queued for deferred removal but not yet flushed (so counts reflect
#| the post-walk state). Primarily useful for tests asserting that
#| destroy / unsubscribe-widget cleanup ran.
method subscription-count(--> Int) {
    %!subscriptions.elems - $!pending-unsubscribes.elems
}

# --- Frame tick ---

#|( Process one tick of the store. Drains the event queue (invoking
    handlers, applying effects, possibly enqueuing more events — capped
    at 100 iterations to prevent infinite loops), then walks every
    subscription and compares its current value against the previous
    one.

    The subscription walk is skipped on ticks where the event queue was
    empty I<and> every subscription has already been primed with its
    initial value. With nothing new in the store, no subscription value
    can have changed — walking them would be wasted work. Registering
    a new subscription flips the prime flag so the next tick initializes
    it regardless of event activity.

    Called automatically by C<Selkie::App.run> each frame. Call
    explicitly only when you need to force state resolution outside
    the main loop (e.g. bootstrapping state before C<run> starts). )
method tick(--> Bool) {
    my $had-events = self!process-queue;
    # Push-based path subs: fire only subscribers whose paths
    # overlap with writes that happened during this tick (or any
    # writes left over from pre-tick bootstrap). Zero cost on idle
    # ticks where the store wasn't written.
    my $had-writes = @!dirty-paths.elems > 0;
    self!flush-push-subs if $had-writes;
    # Pull-based computed/callback subs: still walked every tick
    # that had events (or was the first tick after a new sub was
    # added and hasn't been primed yet).
    if $had-events || !$!subs-primed {
        self!check-subscriptions;
        $!subs-primed = True;
    }
    # Signal "activity happened this tick" back to the event loop so
    # it can keep the tick rate hot instead of falling to the idle
    # ladder. Priming is internal and doesn't count as real activity.
    ($had-events || $had-writes).Bool;
}

#|( Drain C<@!dirty-paths> and fire every push subscription whose
    bound path overlaps with any written path — where "overlaps"
    means either path is a prefix of the other (ancestor / descendant
    / exact). Dedupe: a sub only fires once per flush even if
    multiple writes match it. After dispatching, the dirty-path set
    is cleared. Firing still respects value-change semantics:
    C<!values-equal> gates whether C<&callback> / C<mark-dirty>
    actually runs, so no-op writes don't produce spurious fires. )
method !flush-push-subs() {
    # Same defer wrapper as !check-subscriptions — see "Mutation
    # safety" in the module Pod. Path-callbacks fired from here can
    # call unsubscribe / unsubscribe-widget; those calls queue and
    # apply at walk exit.
    $!in-subscription-walk = True;
    LEAVE {
        $!in-subscription-walk = False;
        self!flush-pending-unsubscribes;
    }

    my @writes = @!dirty-paths;
    @!dirty-paths = ();

    my %to-fire;   # sub-id → True (dedupe within a flush)

    for @writes -> @write {
        # Ancestor side: walk every prefix of @write and look up
        # exact-path subscribers at that prefix depth. Includes the
        # empty prefix (watch-everything root sub).
        for 0 .. @write.elems -> $len {
            my $prefix-key = path-key(@write[^$len]);
            next unless %!push-subs-by-key{$prefix-key}:exists;
            %to-fire{$_} = True for %!push-subs-by-key{$prefix-key}.list;
        }
        # Descendant side: any sub whose bound path has @write as
        # a prefix (and is strictly longer, so we don't double-count
        # the exact match captured by the ancestor loop above).
        my $write-prefix = path-key(@write);
        for %!push-subs-by-key.kv -> $key, @sub-ids {
            next if $key eq $write-prefix;  # exact covered by ancestor loop
            next unless $key.starts-with(
                $write-prefix eq '' ?? '' !! $write-prefix ~ "\0"
            );
            %to-fire{$_} = True for @sub-ids.list;
        }
    }

    for %to-fire.keys -> $sub-id {
        next if $!pending-unsubscribes{$sub-id};
        next unless %!subscriptions{$sub-id}:exists;
        my %sub := %!subscriptions{$sub-id};
        my $current = self.get-in(|%sub<path>);
        # On the structural-comparison path (default), capture a fresh
        # snapshot for both the comparison and the new last-value.
        # The live $current would alias the previous last-value when
        # callers update via assoc-in (which mutates in place), making
        # eqv return True and silently suppressing the fire.
        my $deep = ?%sub<deep>;
        my $current-snap = $deep ?? self!snapshot-value($current) !! $current;
        next if self!values-equal($current-snap, %sub<last-value>, :$deep);
        if $!debug-subscriptions {
            self!log-line("  push-sub[$sub-id] fired: " ~ self!fmt-value($current));
        }
        %sub<last-value> = $current-snap;
        %sub<widget>.mark-dirty if %sub<widget>.defined;
        if (%sub<type> // '') eq 'path-callback' && %sub<callback>.defined {
            %sub<callback>($current);
        }
    }
}

method !process-queue(--> Bool) {
    return False unless @!event-queue;

    my $max-iterations = 100;
    my $iteration = 0;

    while @!event-queue && $iteration++ < $max-iterations {
        my @batch = @!event-queue;
        @!event-queue = ();

        for @batch -> %entry {
            my $event = %entry<event>;
            my %payload = %entry<payload>;

            if $!debug-dispatches {
                my $payload-str = %payload.elems
                    ?? %payload.kv.map(-> $k, $v { "$k=" ~ self!fmt-value($v) }).join(' ')
                    !! '';
                self!log-line("dispatch $event $payload-str");
            }

            my @handlers = |(%!handlers{$event} // []);
            if $!debug-dispatches && @handlers == 0 {
                self!log-line("  (no handler)");
            }
            for @handlers -> &handler {
                # Event handlers get the same isolation as effect
                # handlers — a buggy `register-handler` callback
                # shouldn't kill the dispatch loop and crash the TUI.
                # Re-entrance guard skips the route for failures
                # inside the __effect-error chain itself.
                my @effects;
                {
                    CATCH {
                        default {
                            self!log-line("[event-handler-error] $event: {.message}")
                                if $!debug-dispatches;
                            unless $event eq '__effect-error' {
                                self.dispatch('__effect-error',
                                    effect-name => "event-handler[$event]",
                                    error       => .message,
                                    exception   => $_,
                                    backtrace   => .backtrace.full.Str,
                                    params      => %payload,
                                );
                            }
                        }
                    }
                    @effects = handler(self, %payload);
                }
                self!apply-effects(@effects, :event($event)) if @effects;
            }
        }
    }

    True;
}

method !apply-effects(@effects, Str :$event) {
    for @effects -> $fx {
        next unless $fx ~~ Pair | Associative;

        if $fx ~~ Pair {
            self!run-effect($fx.key, $fx.value, :$event);
        } elsif $fx ~~ Associative {
            for $fx.kv -> $fx-name, $fx-params {
                self!run-effect($fx-name, $fx-params, :$event);
            }
        }
    }
}

method !run-effect(Str:D $fx-name, $fx-params, Str :$event) {
    if $!debug-effects {
        self!log-line("  → $fx-name: " ~ self!fmt-value($fx-params));
    }
    my &handler = %!fx-handlers{$fx-name};
    unless &handler {
        self!log-line("    (unknown effect '$fx-name')") if $!debug-effects;
        return;
    }
    {
        # Isolate handler exceptions AND payload-shape violations: a
        # buggy effect handler — or a handler that passes the wrong
        # payload shape upstream — shouldn't tear out of the dispatch
        # loop and bring down the whole app. The failure is logged
        # and routed back into the event queue as `__effect-error`
        # so apps can register a handler that surfaces failures
        # (toast, modal, telemetry) instead of debugging through
        # stderr behind notcurses's alt-screen.
        CATCH {
            default {
                self!log-line("[effect-error] $fx-name: {.message}")
                    if $!debug-effects;
                # Re-entrance guard: if the failing effect IS the
                # error-event handler chain, drop the failure to avoid
                # infinite recursion. We've already logged it.
                unless $fx-name eq '__effect-error' {
                    self.dispatch('__effect-error',
                        effect-name => $fx-name,
                        error       => .message,
                        exception   => $_,
                        backtrace   => .backtrace.full.Str,
                        params      => $fx-params,
                    );
                }
            }
        }
        # Effect payloads must be Associative. The dispatcher used to
        # wrap bare scalars as `{ value => $x }` automatically — but
        # that silently rewrote the shape so handlers got payloads
        # they didn't expect. Now we throw with a clear migration
        # message. The throw is caught above and routed to
        # __effect-error rather than killing the dispatch loop.
        unless $fx-params ~~ Associative {
            die "Effect '$fx-name' payload must be Associative, got "
              ~ "{$fx-params.^name}. Wrap it: \{ value => \$x \}, "
              ~ "or pass an empty Hash for no payload.";
        }
        handler(self, $fx-params);
    }
}

method !check-subscriptions() {
    # See "Mutation safety" in the module Pod. The flag tells
    # `unsubscribe` to queue removals; the LEAVE block runs whether
    # we exit normally or by exception, so we never wedge the store.
    $!in-subscription-walk = True;
    LEAVE {
        $!in-subscription-walk = False;
        self!flush-pending-unsubscribes;
    }

    # Typed eager Array snapshot: assignment to `Str:D @ids` throws
    # X::TypeCheck::Assignment loudly if any key isn't a defined Str
    # (instead of corrupting an unrelated downstream `:exists` call).
    # The Array binding is an explicit container slot that the spesh
    # optimiser cannot fuse away — `.keys.List` was insufficient in
    # practice for the same purpose.
    my Str:D @ids = %!subscriptions.keys;

    for @ids -> $id {
        next if $!pending-unsubscribes{$id};
        next unless %!subscriptions{$id}:exists;
        my %sub := %!subscriptions{$id};

        # Push-handled types bypass the per-tick walk entirely —
        # they fire from C<!flush-push-subs> on actual writes.
        next if (%sub<type> // '') eq any('path', 'path-callback');

        my $current = do given %sub<type> {
            when 'computed' | 'callback' { %sub<compute>(self) }
        };

        # See the parallel block in !flush-push-subs for the rationale:
        # mutable container compute results need a structural snapshot
        # to detect deep-write changes that leave the container's
        # identity intact.
        my $deep = ?%sub<deep>;
        my $current-snap = $deep ?? self!snapshot-value($current) !! $current;
        unless self!values-equal($current-snap, %sub<last-value>, :$deep) {
            if $!debug-subscriptions {
                self!log-line("  sub[$id] fired: " ~ self!fmt-value($current));
            }
            %sub<last-value> = $current-snap;
            %sub<widget>.mark-dirty if %sub<widget>.defined;
            if %sub<type> eq 'callback' && %sub<callback>.defined {
                %sub<callback>($current);
            }
        }
    }
}

#|( Compare two subscription values for equality. The C<:deep> flag
    skips the C<===> identity shortcut and forces a structural C<eqv>
    compare — necessary for subscriptions over mutable nested data
    where the in-place mutation leaves the container's identity
    unchanged but its contents differ. Set by default on all subscribe
    paths; opt out via C<:identity-check-only> on the C<subscribe*>
    methods when the watched value is a fresh allocation per write. )
method !values-equal($a, $b, Bool :$deep --> Bool) {
    return True if !$a.defined && !$b.defined;
    return False if !$a.defined || !$b.defined;
    return True if !$deep && $a === $b;
    # PERF INSTRUMENTATION (temporary): log eqv compares that take >20 ms.
    # Gated on SELKIE_PERF_LOG env var. Writes via spurt :append because
    # Cantina mutes fd 2 to keep stderr from corrupting the TUI; `note`
    # would silently drop. Revert after ComfyUI lag root-caused.
    if %*ENV<SELKIE_PERF_LOG> {
        my $start = now;
        my $eq = try { $a eqv $b };
        my $elapsed = (now - $start).Num;
        if $elapsed > 0.020e0 {
            my $ts = now.Rat.fmt('%.3f');
            # Include WHICH to disambiguate "same object eqv'd" vs
            # "different objects eqv'd" — if WHICHs match, === should
            # have shortcut and the eqv is bogus.
            my $a-id = try { $a.WHICH.Str } // '?';
            my $b-id = try { $b.WHICH.Str } // '?';
            my $a-elems = try { $a.elems } // '?';
            my $b-elems = try { $b.elems } // '?';
            try spurt '/tmp/selkie-perf.log',
                "[$ts] [eqv {$elapsed.fmt('%.4f')}s] {$a.WHAT.^name}\#{$a-id}(elems=$a-elems) vs {$b.WHAT.^name}\#{$b-id}(elems=$b-elems) same-which={$a-id eq $b-id}\n",
                :append;
        }
        return $eq // False;
    }
    my $eq = try { $a eqv $b };
    $eq // False;
}

#|( Recursive deep clone for subscription change-detection. Returns a
    fresh Hash / Array at every container level so subsequent in-place
    mutations of the live store value can't alias back to the captured
    snapshot. Scalar leaves (Str, Int, Num, Bool, type objects) are
    returned as-is — they're immutable, so sharing the reference is
    safe. Used on the structural-comparison path (the default); the
    C<:identity-check-only> fast path skips this work. )
method !snapshot-value($v) {
    return $v unless $v.defined;
    if $v ~~ Associative {
        my %out;
        %out{$_} = self!snapshot-value($v{$_}) for $v.keys;
        return %out;
    }
    if $v ~~ Positional {
        return $v.list.map({ self!snapshot-value($_) }).Array;
    }
    $v;
}

method !deep-merge(%updates) {
    self!merge-into(%!db, %updates, ());
}

method !merge-into(%target, %source, @path-so-far) {
    for %source.kv -> $key, $value {
        my @here = (|@path-so-far, $key);
        if $value ~~ Associative && %target{$key} ~~ Associative {
            self!merge-into(%target{$key}, $value, @here);
        } else {
            %target{$key} = $value;
            # Mark this exact leaf path as dirty. The push-sub flush
            # will also notify any subscriber whose path is a prefix
            # (ancestor) via its prefix walk, so marking every
            # intermediate level would produce duplicate fires.
            self!mark-path-dirty(@here.List);
        }
    }
}

method !mark-path-dirty(@path) {
    @!dirty-paths.push: @path.List;
}

# --- Async effect tracking ---

#| True once C<drain-async> has flipped the store into shutdown mode.
#| Callers (typically the `async` fx) can poll this to short-circuit
#| dispatches that would race against a tearing-down App.
method shutting-down(--> Bool) { $!shutting-down }

method !track-async-effect(Promise $p) {
    $!async-lock.protect: { @!async-effects.push: $p };
}

#|( Wait for every in-flight async-effect worker to complete (or for the
    timeout to elapse), flip the store into shutdown mode so any further
    `async` dispatches no-op, and clear the tracking list. Called from
    C<Selkie::App.shutdown> before notcurses is torn down so completing
    workers can't dispatch into handlers whose native deps are gone.

    Idempotent — a second call is a fast no-op (the list is empty and
    `$!shutting-down` is already True). )
method drain-async(:$timeout = 5) {
    $!shutting-down = True;
    my @snapshot;
    $!async-lock.protect: {
        @snapshot = @!async-effects;
        @!async-effects = ();
    }
    return unless @snapshot;
    await Promise.anyof(Promise.allof(@snapshot), Promise.in($timeout));
}

method !report-async-failure(Str $message, Str $backtrace) {
    self!log-line("[async-effect] $message\n$backtrace") if $!debug-effects;
}
