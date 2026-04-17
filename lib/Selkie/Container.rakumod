=begin pod

=head1 NAME

Selkie::Container - Role for widgets that hold child widgets

=head1 SYNOPSIS

A minimal custom container that stacks its children vertically with a
one-row gap between them:

=begin code :lang<raku>

use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class My::GapBox does Selkie::Container;

method render() {
    my $y = 0;
    for self.children -> $child {
        if $child.plane {
            $child.reposition($y, 0);
            $child.resize($child.sizing.value, self.cols);
        } else {
            $child.init-plane(
                self.plane,
                y => $y, x => 0,
                rows => $child.sizing.value,
                cols => self.cols,
            );
        }
        $child.render;
        $y += $child.sizing.value + 1;   # leave a 1-row gap
    }
    self.clear-dirty;
}

=end code

=head1 DESCRIPTION

C<Selkie::Container> layers on top of L<Selkie::Widget> (C<also does
Selkie::Widget>). Compose it for any widget that owns child widgets —
layouts (C<VBox>, C<HBox>, C<Split>), decorators (C<Border>, C<Modal>),
scrollers (C<ScrollView>).

The role provides:

=item A C<children> list, manipulated via C<add>, C<remove>, C<clear>
=item Automatic store propagation to added children
=item Recursive destruction and subscription cleanup on C<remove> / C<clear>
=item A C<focusable-descendants> walker so C<Selkie::App> can build the Tab cycle
=item A C<!render-children> helper that cascades dirty flags for correct subtree redraws

Your container's job is to implement C<render>, which positions and
sizes each child before rendering it. For typical layouts, lean on
C<VBox>/C<HBox>/C<Split> instead of building your own container from
scratch.

=head1 EXAMPLES

=head2 Adding and removing children

=begin code :lang<raku>

my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
my $header = Selkie::Widget::Text.new(text => 'Hi', sizing => Sizing.fixed(1));
$vbox.add($header);

# Later — remove cleans up the widget's plane, subscriptions, and children
$vbox.remove($header);

=end code

=head2 Rebuilding from scratch

=begin code :lang<raku>

$vbox.clear;                            # destroys all children
$vbox.add($new-a);
$vbox.add($new-b);

=end code

=head2 Writing your own container

If the built-in layouts don't fit, compose C<Selkie::Container> directly
and implement C<render>. Use C<!render-children> (inherited) to cascade
dirty flags and render each child — this ensures subtree correctness
when the container is dirty:

=begin code :lang<raku>

method render() {
    self!layout-children;      # your own positioning logic
    self!render-children;      # handles dirty cascade + per-child render
    self.clear-dirty;
}

=end code

=head1 SEE ALSO

=item L<Selkie::Widget> — the base role C<Container> builds on
=item L<Selkie::Layout::VBox>, L<Selkie::Layout::HBox>, L<Selkie::Layout::Split> — the built-in containers
=item L<Selkie::Widget::Border>, L<Selkie::Widget::Modal> — decorators that also compose C<Container>

=end pod

unit role Selkie::Container;

use Selkie::Widget;
use Selkie::Event;

also does Selkie::Widget;

has @!children;

#| The current list of children, in insertion order. Immutable list — to
#| modify, use C<add>, C<remove>, or C<clear>.
method children(--> List) { @!children.List }

#|( Add a child widget. The child's C<parent> is set, the store is
    propagated to it (and its subtree), and the container is marked
    dirty. Returns the added child for chaining. )
method add(Selkie::Widget $child --> Selkie::Widget) {
    $child.parent = self;
    self!propagate-store($child) if self.store;
    @!children.push($child);
    self.mark-dirty;
    $child;
}

method !propagate-store(Selkie::Widget $widget) {
    $widget.set-store(self.store);
    if $widget ~~ Selkie::Container {
        for $widget.children -> $child {
            self!propagate-store($child);
        }
    }
    if $widget.can('content') && $widget.content.defined {
        self!propagate-store($widget.content);
    }
}

#|( Remove and destroy a specific child. Unsubscribes the child and its
    entire subtree from the store before destroying. No-op if the given
    widget isn't actually a child. )
method remove(Selkie::Widget $child) {
    self!unsubscribe-tree($child);
    $child.destroy;
    @!children = @!children.grep(* !=== $child);
    self.mark-dirty;
}

#|( Remove and destroy every child. Useful before rebuilding the
    container's contents from scratch (e.g. in a subscription callback
    that regenerates a list). )
method clear() {
    self!unsubscribe-tree($_) for @!children;
    .destroy for @!children;
    @!children = ();
    self.mark-dirty;
}

method !unsubscribe-tree(Selkie::Widget $widget) {
    $widget.store.unsubscribe-widget($widget) if $widget.store;
    if $widget ~~ Selkie::Container {
        for $widget.children -> $child {
            self!unsubscribe-tree($child);
        }
    }
    # Border / Modal hold their child under `.content`, not `.children`.
    # Skipping them here used to leak subscriptions onto widgets whose
    # planes were already freed by the destroy cascade — the next store
    # tick would then re-dispatch into a dead widget's render / apply-
    # style path (ncplane_* on a freed plane = SIGBUS).
    if $widget.can('content') {
        my $c = $widget.content;
        self!unsubscribe-tree($c) if $c.defined;
    }
}

#|( Render each child, cascading dirty to the whole subtree if the
    container itself is dirty. This is the rendering helper you almost
    always want in a custom container's C<render> method — it handles
    the "parent dirty ⇒ children also need redrawing" rule correctly.

    Private so composed classes can call it as C<self!render-children>. )
method !render-children() {
    my $cascade = self.is-dirty;
    for @!children -> $child {
        $child.mark-dirty if $cascade && !$child.is-dirty;
        $child.render if $child.is-dirty;
    }
}

#|( Park self plus every child/content recursively. Container override
    of Widget.park — without this, swapping a container off-screen
    only moves the container's own plane; descendants whose visibility
    isn't tied to their parent's plane position (e.g. Image's sprixel,
    Modal's bg-plane) keep showing on terminal. )
method park() {
    self.reposition(10_000, 0) if self.plane;
    for @!children -> $child {
        $child.park;
    }
    if self.can('content') && self.content.defined {
        self.content.park;
    }
}

#|( Depth-first sequence of focusable descendants. Used by C<Selkie::App>
    to build the Tab/Shift-Tab cycle. Walks children recursively,
    yielding any whose C<focusable> is True. Override if your container
    needs a non-standard traversal order. )
method focusable-descendants(--> Seq) {
    gather {
        for @!children -> $child {
            take $child if $child.focusable;
            if $child ~~ Selkie::Container {
                .take for $child.focusable-descendants;
            }
        }
    }
}

#|( Destroy the container and every child recursively. Called automatically
    when the widget goes out of scope or its parent calls C<remove>. )
method destroy() {
    .destroy for @!children;
    @!children = ();
    self!destroy-plane;
}
