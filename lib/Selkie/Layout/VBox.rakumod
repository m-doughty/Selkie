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
use Selkie::Layout::Allocate;

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

#| Re-layout children when the parent resizes. Re-runs the same fixed →
#| percent → flex allocation as the initial layout, so children's
#| relative sizing is preserved across resizes. Idempotent on no-size
#| changes.
method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
    self!layout-children if self.plane;
}

method !layout-children() {
    my @kids = self.children;
    return unless @kids;

    my UInt $width = self.cols;
    my @allocs = allocate-along-axis(@kids, self.rows);

    # Position and resize children, propagate viewport
    my UInt $cy = 0;
    my Int $parent-abs-y = self.abs-y;
    my Int $parent-abs-x = self.abs-x;
    for @kids.kv -> $i, $child {
        my UInt $h = @allocs[$i];
        if $h == 0 {
            # Zero-row allocation. A child whose previous layout pass
            # gave it rows but now gets nothing: without an action
            # here the child's plane keeps its old size and position,
            # which can easily fall outside our current bounds (e.g.,
            # avatar-col VBox's flex Text spacer collapsing from 4
            # rows to 0 leaves a 4-row Text plane parked at relative
            # (5, 0) — sitting BELOW our plane, painting empty cells
            # over the next sibling / border / row beneath us).
            # Park the plane off-viewport so its cells render
            # harmlessly. The plane comes back into bounds on the
            # next layout pass that gives the child a non-zero
            # allocation, via the standard reposition + handle-resize
            # path.
            $child.park if $child.plane;
            next;
        }

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
