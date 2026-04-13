=begin pod

=head1 NAME

Selkie::Test::Tree - Find and assert on widgets inside a built tree

=head1 SYNOPSIS

=begin code :lang<raku>

use Test;
use Selkie::Test::Tree;
use Selkie::Widget::Button;

# $root is some layout tree built by your app code
my $save-btn = find-widget $root, -> $w {
    $w ~~ Selkie::Widget::Button && $w.label eq 'Save';
};
ok $save-btn.defined, 'Save button exists';

my @all-buttons = find-widgets $root, -> $w { $w ~~ Selkie::Widget::Button };
is @all-buttons.elems, 3, 'three buttons total';

contains-widget-ok $root, $save-btn, 'save button reachable from root';

done-testing;

=end code

=head1 DESCRIPTION

When a widget tree is built by a subscription callback or a factory
helper, you often don't hold direct references to every child. These
helpers walk the tree (descending through C<Container> children and
C<Border>/C<Modal> content) so tests can locate widgets by predicate.

The C<walk> function is the underlying iterator; the other helpers
build on it. Write C<find-widget($root, &pred)> for "first match" and
C<find-widgets($root, &pred)> for "all matches". The predicate is any
C<Callable> that takes a widget and returns a truthy value.

=head1 EXAMPLES

=head2 Find by widget type

=begin code :lang<raku>

my $first-input = find-widget $root,
    -> $w { $w ~~ Selkie::Widget::TextInput };

=end code

=head2 Find by attribute

=begin code :lang<raku>

my $title-bar = find-widget $root, -> $w {
    $w ~~ Selkie::Widget::Text && $w.text.starts-with('Settings');
};

=end code

=head2 Assert the tree's shape

=begin code :lang<raku>

is find-widgets($root, * ~~ Selkie::Widget::Button).elems, 2, 'two buttons';
is find-widgets($root, * ~~ Selkie::Widget::ListView).elems, 1, 'one list';

=end code

=head2 Verify a widget is still reachable

Useful to catch regressions where a widget gets destroyed but tests
still held a reference:

=begin code :lang<raku>

contains-widget-ok $root, $my-input, 'input still in the tree';

=end code

=head1 SEE ALSO

=item L<Selkie::Container> — provides the C<children> list C<walk> descends through
=item L<Selkie::Widget::Border>, L<Selkie::Widget::Modal> — walked through their C<content>

=end pod

unit module Selkie::Test::Tree;

use Test;
use Selkie::Widget;
use Selkie::Container;

#|( Iterate every widget reachable from C<$root>, depth-first. Yields
    C<$root> itself first, then descends through C<Container.children>
    and any C<.content> (for Border/Modal). Lazy — safe to short-circuit
    with C<.first>. )
sub walk(Selkie::Widget $root --> Seq) is export {
    gather {
        take $root;
        if $root ~~ Selkie::Container {
            for $root.children -> $child {
                .take for walk($child);
            }
        }
        if $root.can('content') && $root.content.defined {
            .take for walk($root.content);
        }
    }
}

#|( Return the first widget matching the predicate, or C<Nil>. The
    predicate can be any C<Callable> taking a widget; smartmatch also
    works thanks to Raku's C<*> whatever star:

        find-widget $root, * ~~ Selkie::Widget::Button;
        find-widget $root, -> $w { $w.focusable };
)
sub find-widget(Selkie::Widget $root, &predicate --> Selkie::Widget) is export {
    walk($root).first(&predicate) // Selkie::Widget;
}

#| Return every widget in the tree matching the predicate, in walk order.
sub find-widgets(Selkie::Widget $root, &predicate --> List) is export {
    walk($root).grep(&predicate).List;
}

#|( Test assertion: C<$target> is reachable from C<$root>. Uses identity
    comparison (C<===>), so it's checking the same widget instance. )
sub contains-widget-ok(Selkie::Widget $root, Selkie::Widget $target, Str:D $desc) is export {
    ok walk($root).first(* === $target).defined, $desc;
}
