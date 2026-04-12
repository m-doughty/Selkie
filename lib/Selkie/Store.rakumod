unit class Selkie::Store;

use Selkie::Widget;

has %!db;
has @!event-queue;
has %!handlers;          # event-name → Array[&handler]
has %!fx-handlers;       # fx-name → &handler
has %!subscriptions;     # sub-id → Hash{ path|compute, last-value, widget }

submethod TWEAK() {
    # Built-in effects
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

method db(--> Hash) { %!db }

method get-in(*@path) {
    my $current = %!db;
    for @path -> $key {
        return Nil unless $current ~~ Associative;
        return Nil unless $current{$key}:exists;
        $current = $current{$key};
    }
    $current<>;
}

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

method dispatch(Str:D $event, *%payload) {
    @!event-queue.push({ :$event, :%payload });
}

method register-handler(Str:D $event, &handler) {
    %!handlers{$event} = [] unless %!handlers{$event}:exists;
    %!handlers{$event}.push(&handler);
}

# --- Effects ---

method register-fx(Str:D $fx-name, &handler) {
    %!fx-handlers{$fx-name} = &handler;
}

# --- Subscriptions ---

# Sentinel value — never matches any real value
my constant $UNSET = class { method WHICH() { 'UNSET' } }.new;

method subscribe(Str:D $id, @path, Selkie::Widget $widget) {
    %!subscriptions{$id} = {
        type       => 'path',
        path       => @path.List,
        last-value => $UNSET,  # forces dirty on first tick
        widget     => $widget,
    };
}

method subscribe-computed(Str:D $id, &compute, Selkie::Widget $widget) {
    %!subscriptions{$id} = {
        type       => 'computed',
        compute    => &compute,
        last-value => $UNSET,  # forces dirty on first tick
        widget     => $widget,
    };
}

method subscribe-with-callback(Str:D $id, &compute, &callback, Selkie::Widget $widget) {
    %!subscriptions{$id} = {
        type       => 'callback',
        compute    => &compute,
        callback   => &callback,
        last-value => $UNSET,
        widget     => $widget,
    };
}

method unsubscribe(Str:D $id) {
    %!subscriptions{$id}:delete;
}

method unsubscribe-widget(Selkie::Widget $widget) {
    my @to-remove = %!subscriptions.grep(*.value<widget> === $widget).map(*.key);
    %!subscriptions{$_}:delete for @to-remove;
}

# --- Frame tick ---

method tick() {
    self!process-queue;
    self!check-subscriptions;
}

method !process-queue() {
    # Drain the queue — handlers may enqueue more events via :dispatch fx
    # Limit iterations to prevent infinite loops
    my $max-iterations = 100;
    my $iteration = 0;

    while @!event-queue && $iteration++ < $max-iterations {
        my @batch = @!event-queue;
        @!event-queue = ();

        for @batch -> %entry {
            my $event = %entry<event>;
            my %payload = %entry<payload>;

            my @handlers = |(%!handlers{$event} // []);
            for @handlers -> &handler {
                my @effects = handler(self, %payload);
                self!apply-effects(@effects);
            }
        }
    }
}

method !apply-effects(@effects) {
    for @effects -> $fx {
        next unless $fx ~~ Pair | Associative;

        if $fx ~~ Pair {
            my $fx-name = $fx.key;
            my $fx-params = $fx.value;
            my &handler = %!fx-handlers{$fx-name};
            if &handler {
                handler(self, $fx-params ~~ Associative ?? $fx-params !! { value => $fx-params });
            }
        } elsif $fx ~~ Associative {
            for $fx.kv -> $fx-name, $fx-params {
                my &handler = %!fx-handlers{$fx-name};
                if &handler {
                    handler(self, $fx-params ~~ Associative ?? $fx-params !! { value => $fx-params });
                }
            }
        }
    }
}

method !check-subscriptions() {
    for %!subscriptions.values -> %sub {
        my $current = do given %sub<type> {
            when 'path'     { self.get-in(|%sub<path>) }
            when 'computed' | 'callback' { %sub<compute>(self) }
        };

        unless self!values-equal($current, %sub<last-value>) {
            %sub<last-value> = $current;
            %sub<widget>.mark-dirty if %sub<widget>.defined;
            # Callback subscriptions also invoke the callback with the new value
            if %sub<type> eq 'callback' && %sub<callback>.defined {
                %sub<callback>($current);
            }
        }
    }
}

method !values-equal($a, $b --> Bool) {
    return True if !$a.defined && !$b.defined;
    return False if !$a.defined || !$b.defined;
    # Identity short-circuit for the common case of subscriptions returning
    # the same reference twice — cheap and avoids deep comparison cost on
    # large structures.
    return True if $a === $b;
    # Otherwise use value equality. eqv falls back to identity for arbitrary
    # objects without an `eqv` operator, but does deep comparison for
    # Iterables, Associatives, and standard scalars. Wrapped in a try in
    # case some custom type's eqv throws — treat that as "not equal".
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
