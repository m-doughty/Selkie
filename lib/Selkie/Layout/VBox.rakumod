=begin pod

=head1 NAME

Selkie::Layout::VBox - Arrange children top to bottom

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Layout::VBox;
use Selkie::Sizing;

my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$vbox.add: $header;    # Sizing.fixed(1)
$vbox.add: $body;      # Sizing.flex
$vbox.add: $footer;    # Sizing.fixed(1)

=end code

=head1 DESCRIPTION

C<VBox> stacks children vertically and allocates rows according to each
child's L<Selkie::Sizing>:

=item B<Fixed> children get exactly the rows they ask for.
=item B<Percent> children get C<n%> of the parent's total rows.
=item B<Flex> children share whatever rows are left over, weighted by flex factor.

Columns are set to the full parent width for every child.

VBox is a L<Selkie::Container>, so it inherits C<add>, C<remove>,
C<clear>, and focusable-descendants handling. All children must compose
C<Selkie::Widget>.

=head1 EXAMPLES

=head2 Classic three-pane stack

=begin code :lang<raku>

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);

$root.add: Selkie::Widget::Text.new(
    text   => ' Selkie App',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

$root.add: $main-content;   # sizing => Sizing.flex — fills middle

$root.add: Selkie::Widget::Text.new(
    text   => ' Ctrl+Q: quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x666666),
);

=end code

=head2 Weighted distribution

=begin code :lang<raku>

my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$vbox.add: $preview;   # Sizing.flex(2) — gets two-thirds
$vbox.add: $output;    # Sizing.flex    — gets one-third

=end code

=head1 SEE ALSO

=item L<Selkie::Layout::HBox> — horizontal version of the same layout
=item L<Selkie::Layout::Split> — two-pane split with a draggable divider ratio
=item L<Selkie::Sizing> — the fixed/percent/flex sizing model

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class Selkie::Layout::VBox does Selkie::Container;

#|( Perform layout and render each child. Called automatically by the
    render cycle. The layout pass allocates rows according to every
    child's C<Sizing>: fixed first, then percent, then flex shares the
    rest. )
method render() {
    self!layout-children;
    self!render-children;
    self.clear-dirty;
}

#|( Resize cascade: own plane + re-layout children so allocations
    propagate synchronously through the subtree, without waiting for
    the next render pass. Layout-children calls handle-resize on each
    child so the recursion continues. )
method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
    # layout-children can't run meaningfully without a plane (it would
    # try to init-plane children against a null parent). When called on
    # an unmounted subtree, just update our own dims; the first render
    # after mount handles the layout.
    self!layout-children if self.plane;
}

method !layout-children() {
    my @kids = self.children;
    return unless @kids;

    my UInt $available = self.rows;
    my UInt $width = self.cols;

    # Pass 1: allocate fixed and percent
    my @allocs = @kids.map({ 0 });
    my Numeric $total-flex = 0;

    for @kids.kv -> $i, $child {
        given $child.sizing.mode {
            when SizeFixed {
                @allocs[$i] = $child.sizing.value.UInt min $available;
                $available -= @allocs[$i];
            }
            when SizePercent {
                @allocs[$i] = (self.rows * $child.sizing.value / 100).floor.UInt min $available;
                $available -= @allocs[$i];
            }
            when SizeFlex {
                $total-flex += $child.sizing.value;
            }
        }
    }

    # Pass 2: distribute remaining to flex
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
        # Give any rounding remainder to the last flex child
        if $remaining > 0 {
            for @kids.kv.reverse -> $child, $i {
                if $child.sizing.mode ~~ SizeFlex {
                    @allocs[$i] += $remaining;
                    last;
                }
            }
        }
    }

    # Pass 3: position and resize children, propagate viewport
    my UInt $cy = 0;
    my Int $parent-abs-y = self.abs-y;
    my Int $parent-abs-x = self.abs-x;
    for @kids.kv -> $i, $child {
        my UInt $h = @allocs[$i];
        next unless $h > 0;

        if $child.plane {
            $child.reposition($cy, 0);
            # handle-resize cascades into the child subtree so nested
            # containers also propagate new dims. Short-circuits when
            # dims are unchanged, so this is cheap during normal renders.
            $child.handle-resize($h, $width);
        } else {
            $child.init-plane(self.plane, y => $cy, x => 0, rows => $h, cols => $width);
        }
        $child.set-viewport(
            abs-y => $parent-abs-y + $cy,
            abs-x => $parent-abs-x,
            rows  => $h,
            cols  => $width,
        );
        $cy += $h;
    }
}
