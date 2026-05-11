=begin pod

=head1 NAME

Selkie::Tree - Tree-walking helpers used by widgets that need to reach
beyond their own subtree

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Tree;

# Mark every widget whose plane intersects this absolute screen rect
# as dirty — used by Image.destroy-blit-plane to repaint cells under
# the removed sprixel.
mark-widgets-in-rect-dirty(
    abs-y => 5,  abs-x => 10,
    rows  => 4,  cols  => 16,
);

# The active modal (or Nil), used by widgets that need to skip
# rendering when occluded.
my $modal = current-active-modal;

=end code

=head1 DESCRIPTION

A small set of free subs that bridge between a widget and the wider
tree it lives in, without requiring the widget to walk up to the
L<Selkie::App> instance manually. L<Selkie::App> at init populates
two class-level provider closures — one returning the live list of
tree roots (active screen + modal stack + toast), the other returning
the active modal — and the helpers here read through them.

This pattern keeps widgets like L<Selkie::Widget::Image> from needing
a circular import on Selkie::App while still letting them participate
in app-level coordination (cell cleanup after sprixel destroy, modal
occlusion checks, etc.).

=end pod

unit module Selkie::Tree;

# --- Tree-roots provider --------------------------------------------------
#
# Closure returning the live list of widget tree roots — typically the
# active screen's root plus every modal in the stack plus the toast
# overlay. Set by Selkie::App at init. Used by C<mark-widgets-in-rect-dirty>
# to find the trees to walk.

my &TREE-ROOTS-PROVIDER = -> { () };

#|( Set the tree-roots provider — a closure returning an iterable of
    widget roots. C<Selkie::App> calls this during init so tree-walking
    helpers can find the live trees without each helper needing a
    direct reference to the app. )
sub set-tree-roots-provider(&p --> Nil) is export {
    &TREE-ROOTS-PROVIDER = &p;
}

#|( The current list of widget tree roots. Used internally by helpers
    in this module; apps don't typically call this directly. )
sub current-tree-roots(--> List) is export {
    TREE-ROOTS-PROVIDER().List;
}

# --- Active-modal provider ------------------------------------------------
#
# Closure returning the topmost open modal widget (or Nil). Set by
# Selkie::App at init. Used by widgets that need to detect occlusion —
# notably L<Selkie::Widget::Image>, which destroys its blit and skips
# rendering when a modal is open and the image is not in its tree.

my &MODAL-PROVIDER = -> { Nil };

#|( Set the active-modal provider — a closure returning the topmost
    open modal widget or Nil. C<Selkie::App> calls this on init. )
sub set-modal-provider(&p --> Nil) is export {
    &MODAL-PROVIDER = &p;
}

#|( The topmost open modal widget, or Nil if no modal is open. )
sub current-active-modal(--> Mu) is export {
    MODAL-PROVIDER();
}

# --- Tree-walking helpers -------------------------------------------------

#|( Walk every tree root and mark dirty any widget whose absolute screen
    bounds intersect the given rectangle. Used by sprixel-bearing
    widgets after they destroy a blit-plane: the cells under the
    removed sprixel may belong to a widget that has nothing else
    changing this frame, so without an explicit dirty mark the widget
    won't repaint and the cells will continue to show whatever was
    cached pre-sprixel-removal. Cheap walk; called once per blit
    teardown. )
sub mark-widgets-in-rect-dirty(
    Int  :$abs-y!,
    Int  :$abs-x!,
    UInt :$rows!,
    UInt :$cols!,
    --> Nil
) is export {
    return if $rows == 0 || $cols == 0;
    my Int $rect-bottom = $abs-y + $rows.Int;
    my Int $rect-right  = $abs-x + $cols.Int;

    sub visit($w) {
        return without $w;
        # Rectangles overlap iff
        #   !(a.right <= b.left || b.right <= a.left ||
        #     a.bottom <= b.top  || b.bottom <= a.top)
        my Int $w-bottom = $w.abs-y + $w.rows.Int;
        my Int $w-right  = $w.abs-x + $w.cols.Int;
        my Bool $intersects = !(
               $w-right     <= $abs-x
            || $rect-right  <= $w.abs-x
            || $w-bottom    <= $abs-y
            || $rect-bottom <= $w.abs-y
        );
        $w.mark-dirty if $intersects && !$w.is-dirty;
        if $w.^can('children') {
            visit($_) for $w.children;
        }
        if $w.^can('content') {
            my $c = $w.content;
            visit($c) if $c.defined;
        }
    }

    visit($_) for current-tree-roots();
}
