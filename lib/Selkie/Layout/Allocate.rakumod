=begin pod

=head1 NAME

Selkie::Layout::Allocate - Shared sizing-allocation pass for box layouts

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Layout::Allocate;
use Selkie::Sizing;

# A custom container that arranges children along the row axis:
my @allocs = allocate-along-axis(@kids, self.rows);

# `@allocs` is parallel to `@kids`; @allocs[$i] is the cell-count
# the layout assigns to the corresponding child. Position the children
# yourself — Allocate doesn't know about reposition / set-viewport.

=end code

=head1 DESCRIPTION

C<allocate-along-axis> runs the three-pass sizing algorithm that both
L<Selkie::Layout::VBox> and L<Selkie::Layout::HBox> use to decide how
much room each child gets:

=item B<Pass 1.> Walk the children. Children with C<Sizing.fixed($n)>
take C<$n> cells (clamped by remaining space). Children with
C<Sizing.percent($n)> take C<$n%> of the original axis total (also
clamped). Flex children defer; their flex factors are accumulated into
a running total.

=item B<Pass 2.> Distribute whatever space remains among flex children,
weighted by their flex factor relative to the total flex weight. Each
flex share is floored, so several flex children can leave a few
cells unspent.

=item B<Pass 3.> Hand any rounding remainder to the highest-index
flex child. This keeps the box exactly filled and avoids rounding
drift on resizes.

The function returns an C<Array[UInt]> aligned with C<@kids>; callers
are responsible for positioning and propagating viewport bounds, since
those depend on which axis is being laid out.

=head2 Why a free sub and not a base role?

VBox and HBox differ only in axis: VBox stacks rows, HBox stacks
columns. Pass 3 (positioning) is axis-specific — it has to call
C<reposition($cy, 0)> versus C<reposition(0, $cx)>, plus
C<set-viewport> with axis-specific named args. Bridging that into a
shared role would obscure the layout code without saving lines, so
the extraction stops at the axis-agnostic part: the allocation math.

=end pod

unit module Selkie::Layout::Allocate;

use Selkie::Sizing;

#|( Compute per-child allocations along a single axis, given the total
    axis size. Returns an Array[UInt] where `@allocs[$i]` is the cell
    count for `@kids[$i]`. Sum of allocations equals C<$total> when
    flex children are present and C<$total> is non-zero; otherwise
    allocations may sum to less than C<$total>.

    Algorithm:

    =item Fixed children take C<value> cells (clamped by remaining).
    =item Percent children take C<value%> of C<$total> (also clamped).
    =item Flex children share whatever remains, weighted by C<value>;
          the highest-index flex child collects any rounding remainder.
)
sub allocate-along-axis(@kids, UInt $total --> Array) is export {
    my @allocs = @kids.map({ 0 });
    return @allocs unless @kids;

    my UInt $available = $total;
    my Numeric $total-flex = 0;

    # Pass 1: fixed and percent children consume $available.
    for @kids.kv -> $i, $child {
        given $child.sizing.mode {
            when SizeFixed {
                @allocs[$i] = $child.sizing.value.UInt min $available;
                $available -= @allocs[$i];
            }
            when SizePercent {
                @allocs[$i] = ($total * $child.sizing.value / 100).floor.UInt min $available;
                $available -= @allocs[$i];
            }
            when SizeFlex {
                $total-flex += $child.sizing.value;
            }
        }
    }

    # Pass 2: distribute the remainder to flex children proportionally.
    if $total-flex > 0 && $available > 0 {
        my UInt $remaining = $available;
        for @kids.kv -> $i, $child {
            if $child.sizing.mode ~~ SizeFlex {
                my $share = ($available * $child.sizing.value / $total-flex).floor.UInt;
                $share = $share min $remaining;
                @allocs[$i] = $share;
                $remaining -= $share;
            }
        }
        # Pass 3: rounding remainder to the last (highest-index) flex
        # child. `.kv.reverse` flips the (idx, val) pairs into
        # (val, idx) order, so the pointy block reads as
        # `-> $child, $i`, not `-> $i, $child` — easy to misread.
        if $remaining > 0 {
            for @kids.kv.reverse -> $child, $i {
                if $child.sizing.mode ~~ SizeFlex {
                    @allocs[$i] += $remaining;
                    last;
                }
            }
        }
    }

    @allocs;
}
