=begin pod

=head1 NAME

Selkie::Test::Supply - Observation and assertion helpers for widget Supply emissions

=head1 SYNOPSIS

=begin code :lang<raku>

use Test;
use Selkie::Test::Keys;
use Selkie::Test::Supply;
use Selkie::Widget::Button;

my $btn = Selkie::Widget::Button.new(label => 'OK');
$btn.set-focused(True);

# Collect everything a Supply emits during an action
my @emissions = collect-from $btn.on-press, {
    press-key($btn, 'enter');
    press-key($btn, 'space');
};
is @emissions.elems, 2, 'two presses';

# Or assert directly:
emitted-once-ok $btn.on-press, True, 'Enter presses the button', {
    press-key($btn, 'enter');
};

done-testing;

=end code

=head1 DESCRIPTION

Widgets expose user-level events as L<Supply>s — C<on-press>,
C<on-change>, C<on-activate>, etc. Testing them without these helpers
is a tap-collect-assert dance in every test. This module provides the
pattern as three named functions.

Supply emissions from widgets are synchronous — the C<.emit> call in a
handler fires the tap inline — so C<collect-from> works without needing
event-loop integration. The tap is closed automatically at the end of
the block.

=head1 EXAMPLES

=head2 Count emissions

=begin code :lang<raku>

emitted-count-is $list.on-select, 3, 'three cursor moves', {
    press-keys($list, 'down', 'down', 'down');
};

=end code

=head2 Capture and inspect

=begin code :lang<raku>

my @emitted = collect-from $input.on-change, {
    type-text($input, 'hi');
};
is @emitted[*-1], 'hi', 'last emission is the final text';

=end code

=head2 Assert nothing emitted

=begin code :lang<raku>

emitted-count-is $btn.on-press, 0, 'unfocused button ignores key', {
    press-key($btn, 'enter');
};

=end code

=head1 SEE ALSO

=item L<Selkie::Test::Keys> — for synthesising the events that trigger the emissions
=item L<Selkie::Test::Store> — for store-dispatch-based tests

=end pod

unit module Selkie::Test::Supply;

use Test;

#|( Tap a Supply, run a block, return every emission in order. The tap
    is closed when the block finishes. Emissions are collected in the
    same thread, so this works for widget Supplies that emit synchronously
    from event handlers. )
sub collect-from(Supply:D $supply, &block --> List) is export {
    my @emitted;
    my $tap = $supply.tap: -> $v { @emitted.push($v) };
    block();
    $tap.close;
    @emitted.List;
}

#|( Assertion: the supply emitted exactly once, with the given value,
    during the block. Produces two test lines — one for the count, one
    for the value (only if the count was 1). )
sub emitted-once-ok(Supply:D $supply, $expected, Str:D $desc, &block) is export {
    my @got = collect-from($supply, &block);
    my $count-ok = ok @got.elems == 1, "$desc — emitted exactly once";
    if @got.elems == 1 {
        is-deeply @got[0], $expected, "$desc — correct value";
    } else {
        diag "    got {@got.elems} emission(s): {@got.raku}";
    }
}

#|( Assertion: the supply emitted exactly C<$n> times during the block.
    C<$n> may be 0 to assert nothing was emitted. )
sub emitted-count-is(Supply:D $supply, Int:D $n, Str:D $desc, &block) is export {
    my @got = collect-from($supply, &block);
    my $suffix = $n == 1 ?? 'time' !! 'times';
    is @got.elems, $n, "$desc — emitted $n $suffix";
    diag "    got: {@got.raku}" unless @got.elems == $n;
}
