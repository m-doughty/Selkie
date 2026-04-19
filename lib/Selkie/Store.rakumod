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

=head2 Equality semantics

Subscription computes are compared against the previous value with a
two-stage check: identity (C<===>) first, then value equality (C<eqv>)
if that fails. C<eqv> does deep comparison on arrays and hashes, so
subscriptions that return the same content in a fresh array instance
don't fire spuriously.

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

has IO::Handle $!debug-log;
has Bool $!debug-dispatches    = False;
has Bool $!debug-effects       = False;
has Bool $!debug-subscriptions = False;

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
    return unless $!debug-log.defined;
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
        my &work = %params<work>;
        my $on-success = %params<on-success>;
        my $on-failure = %params<on-failure>;

        start {
            my $result = try { work() };
            if $! {
                $store.dispatch($on-failure, error => $!.message) if $on-failure;
            } else {
                $store.dispatch($on-success, result => $result) if $on-success;
            }
        }
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

#|( Subscribe a widget to a state path. When the value at the path
    changes, the widget is marked dirty on the next tick. The C<$id>
    identifies the subscription for later C<unsubscribe> — use a unique
    name per subscription. )
method subscribe(Str:D $id, @path, Selkie::Widget $widget) {
    %!subscriptions{$id} = {
        type       => 'path',
        path       => @path.List,
        last-value => $UNSET,
        widget     => $widget,
    };
    $!subs-primed = False;
}

#|( Subscribe a widget to a computed value. C<&compute> receives the
    store each tick and should return the value. The widget is marked
    dirty when the return value changes (compared with C<eqv> /
    identity). )
method subscribe-computed(Str:D $id, &compute, Selkie::Widget $widget) {
    %!subscriptions{$id} = {
        type       => 'computed',
        compute    => &compute,
        last-value => $UNSET,
        widget     => $widget,
    };
    $!subs-primed = False;
}

#|( Like C<subscribe-computed>, but also invokes C<&callback> with the
    new value whenever it changes. Use this when your widget needs to
    be re-configured (e.g. C<set-items> on a list, C<set-text> on a
    label), not just re-rendered. )
method subscribe-with-callback(Str:D $id, &compute, &callback, Selkie::Widget $widget) {
    %!subscriptions{$id} = {
        type       => 'callback',
        compute    => &compute,
        callback   => &callback,
        last-value => $UNSET,
        widget     => $widget,
    };
    $!subs-primed = False;
}

#| Remove a subscription by its id. No-op if the id isn't registered.
method unsubscribe(Str:D $id) {
    %!subscriptions{$id}:delete;
}

#|( Remove every subscription bound to a widget. Called automatically by
    C<Selkie::Container> when a child is removed — you rarely call this
    yourself. )
method unsubscribe-widget(Selkie::Widget $widget) {
    my @to-remove = %!subscriptions.grep(*.value<widget> === $widget).map(*.key);
    %!subscriptions{$_}:delete for @to-remove;
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
method tick() {
    my $had-events = self!process-queue;
    if $had-events || !$!subs-primed {
        self!check-subscriptions;
        $!subs-primed = True;
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
                my @effects = handler(self, %payload);
                self!apply-effects(@effects, :event($event));
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
    if &handler {
        handler(self, $fx-params ~~ Associative ?? $fx-params !! { value => $fx-params });
    } elsif $!debug-effects {
        self!log-line("    (unknown effect '$fx-name')");
    }
}

method !check-subscriptions() {
    for %!subscriptions.kv -> $id, %sub {
        my $current = do given %sub<type> {
            when 'path'     { self.get-in(|%sub<path>) }
            when 'computed' | 'callback' { %sub<compute>(self) }
        };

        unless self!values-equal($current, %sub<last-value>) {
            if $!debug-subscriptions {
                self!log-line("  sub[$id] fired: " ~ self!fmt-value($current));
            }
            %sub<last-value> = $current;
            %sub<widget>.mark-dirty if %sub<widget>.defined;
            if %sub<type> eq 'callback' && %sub<callback>.defined {
                %sub<callback>($current);
            }
        }
    }
}

method !values-equal($a, $b --> Bool) {
    return True if !$a.defined && !$b.defined;
    return False if !$a.defined || !$b.defined;
    return True if $a === $b;
    my $eq = try { $a eqv $b };
    $eq // False;
}

method !deep-merge(%updates) {
    self!merge-into(%!db, %updates);
}

method !merge-into(%target, %source) {
    for %source.kv -> $key, $value {
        if $value ~~ Associative && %target{$key} ~~ Associative {
            self!merge-into(%target{$key}, $value);
        } else {
            %target{$key} = $value;
        }
    }
}
