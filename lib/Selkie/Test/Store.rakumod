=begin pod

=head1 NAME

Selkie::Test::Store - Conveniences for testing handlers and subscriptions

=head1 SYNOPSIS

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

Three helpers for the common test patterns against L<Selkie::Store>:

=item C<mock-store> — build a fresh store, optionally pre-populated with nested initial state
=item C<dispatch-and-tick> — the dispatch + tick boilerplate in one call
=item C<state-at> — splat-style read that's more readable than C<$store.get-in(|@path)>

These aren't assertions themselves — use plain C<is>, C<is-deeply>, etc.
around the returned values. That keeps the helpers composable and lets
you use whatever Test:: style fits.

=head1 EXAMPLES

=head2 Handler testing without a live App

=begin code :lang<raku>

my $store = mock-store;
my $app-handlers = My::App::StoreHandlers.new(:$db);
$app-handlers.register($store);

dispatch-and-tick($store, 'app/init');
is state-at($store, 'active-tab'), 'servers', 'init picks a default tab';

dispatch-and-tick($store, 'tab/select', name => 'logs');
is state-at($store, 'active-tab'), 'logs', 'dispatch changed tab';

=end code

=head2 Subscribing a widget in a test

=begin code :lang<raku>

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

=end code

=head1 SEE ALSO

=item L<Selkie::Store> — the reactive store being tested
=item L<Selkie::Test::Keys>, L<Selkie::Test::Supply> — for UI-level testing

=end pod

unit module Selkie::Test::Store;

use Selkie::Store;

#|( Create a fresh store, optionally pre-populated with nested state.
    The C<:state> hash is deep-merged into the store's C<db> in one
    shot — nested hashes become nested paths.

        my $store = mock-store(state => {
            app  => { count => 0, user => { name => 'Alice' } },
            flag => True,
        });
)
sub mock-store(:%state --> Selkie::Store) is export {
    my $s = Selkie::Store.new;
    seed-state($s, %state) if %state;
    $s;
}

sub seed-state(Selkie::Store $s, %state, *@prefix) {
    for %state.kv -> $k, $v {
        if $v ~~ Associative {
            seed-state($s, $v, |@prefix, $k);
        } else {
            $s.assoc-in(|@prefix, $k, value => $v);
        }
    }
}

#|( Dispatch an event and immediately tick the store, replacing the
    common two-liner in tests.

        dispatch-and-tick($store, 'counter/inc');
        dispatch-and-tick($store, 'user/set', name => 'Bob');

    Equivalent to:

        $store.dispatch($event, |%payload);
        $store.tick;
)
sub dispatch-and-tick(Selkie::Store $store, Str:D $event, *%payload) is export {
    $store.dispatch($event, |%payload);
    $store.tick;
}

#|( Splat-style deep read. Same semantics as C<$store.get-in(|@path)>
    but easier on the eyes in tests:

        is state-at($store, 'app', 'count'), 5, 'incremented';
        is state-at($store, 'counter'), 0, 'reset';
)
sub state-at(Selkie::Store $store, *@path) is export {
    $store.get-in(|@path);
}
