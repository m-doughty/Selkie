NAME
====

Selkie::Test::Store - Conveniences for testing handlers and subscriptions

SYNOPSIS
========

```raku
use Test;
use Selkie::Test::Store;

my $store = mock-store(state => {
    user => { name => 'Alice', roles => <admin> },
    count => 0,
});

$store.register-handler('inc', -> $st, % {
    (db => { count => ($st.get-in('count') // 0) + 1 },);
});

dispatch-and-tick($store, 'inc');
dispatch-and-tick($store, 'inc');

is state-at($store, 'count'), 2, 'count incremented twice';
is state-at($store, 'user', 'name'), 'Alice', 'nested state accessible';

done-testing;
```

DESCRIPTION
===========

Three helpers for the common test patterns against [Selkie::Store](Selkie--Store.md):

  * `mock-store` — build a fresh store, optionally pre-populated with nested initial state

  * `dispatch-and-tick` — the dispatch + tick boilerplate in one call

  * `state-at` — splat-style read that's more readable than `$store.get-in(|@path)`

These aren't assertions themselves — use plain `is`, `is-deeply`, etc. around the returned values. That keeps the helpers composable and lets you use whatever Test:: style fits.

EXAMPLES
========

Handler testing without a live App
----------------------------------

```raku
my $store = mock-store;
my $app-handlers = My::App::StoreHandlers.new(:$db);
$app-handlers.register($store);

dispatch-and-tick($store, 'app/init');
is state-at($store, 'active-tab'), 'servers', 'init picks a default tab';

dispatch-and-tick($store, 'tab/select', name => 'logs');
is state-at($store, 'active-tab'), 'logs', 'dispatch changed tab';
```

Subscribing a widget in a test
------------------------------

```raku
my $text = Selkie::Widget::Text.new(text => '-', sizing => Sizing.fixed(1));
my $store = mock-store;

$store.subscribe-with-callback(
    'mirror',
    -> $s { $s.get-in('count') // 0 },
    -> $n { $text.set-text("count: $n") },
    $text,
);

dispatch-and-tick($store, 'inc');   # (assuming handler registered elsewhere)
is $text.text, 'count: 1', 'subscription callback fired';
```

SEE ALSO
========

  * [Selkie::Store](Selkie--Store.md) — the reactive store being tested

  * [Selkie::Test::Keys](Selkie--Test--Keys.md), [Selkie::Test::Supply](Selkie--Test--Supply.md) — for UI-level testing

### sub mock-store

```raku
sub mock-store(
    :%state
) returns Selkie::Store
```

Create a fresh store, optionally pre-populated with nested state. The `:state` hash is deep-merged into the store's `db` in one shot — nested hashes become nested paths. my $store = mock-store(state => { app => { count => 0, user => { name => 'Alice' } }, flag => True, });

### sub dispatch-and-tick

```raku
sub dispatch-and-tick(
    Selkie::Store $store,
    Str:D $event,
    *%payload
) returns Mu
```

Dispatch an event and immediately tick the store, replacing the common two-liner in tests. dispatch-and-tick($store, 'counter/inc'); dispatch-and-tick($store, 'user/set', name => 'Bob'); Equivalent to: $store.dispatch($event, |%payload); $store.tick;

### sub state-at

```raku
sub state-at(
    Selkie::Store $store,
    *@path
) returns Mu
```

Splat-style deep read. Same semantics as `$store.get-in(|@path)` but easier on the eyes in tests: is state-at($store, 'app', 'count'), 5, 'incremented'; is state-at($store, 'counter'), 0, 'reset';

