=begin pod

=head1 NAME

Selkie::Layout::HBox - Arrange children left to right

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Layout::HBox;
use Selkie::Sizing;

my $row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$row.add: $label;     # Sizing.fixed(8)
$row.add: $input;     # Sizing.flex
$row.add: $button;    # Sizing.fixed(10)

=end code

=head1 DESCRIPTION

C<HBox> arranges children horizontally. Allocation follows the same
three-pass sizing rule as L<Selkie::Layout::VBox>, but operates on
columns instead of rows.

All children get the full parent height; only widths are computed.

=head1 EXAMPLES

=head2 Three-column main layout

The classic file-manager pattern: sidebar + main + details.

=begin code :lang<raku>

my $columns = Selkie::Layout::HBox.new(sizing => Sizing.flex);
$columns.add: $sidebar;        # Sizing.fixed(20)
$columns.add: $main-content;   # Sizing.flex
$columns.add: $details;        # Sizing.fixed(30)

=end code

=head2 A button row

=begin code :lang<raku>

my $buttons = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
$buttons.add: Selkie::Widget::Button.new(label => 'Cancel', sizing => Sizing.flex);
$buttons.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(2));   # spacer
$buttons.add: Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.flex);

=end code

=head1 SEE ALSO

=item L<Selkie::Layout::VBox> — vertical version of the same layout
=item L<Selkie::Layout::Split> — two-pane split with a divider
=item L<Selkie::Sizing> — the sizing model

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class Selkie::Layout::HBox does Selkie::Container;

#|( Perform layout and render each child. Called automatically by the
    render cycle. Columns are allocated using the same three-pass
    strategy as C<VBox>, applied to the width axis. )
method render() {
    self!layout-children;
    self!render-children;
    self.clear-dirty;
}

#| Resize this container's own plane. Children are re-laid-out in
#| C<render>, not here. See VBox for the rationale.
method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
}

method !layout-children() {
    my @kids = self.children;
    return unless @kids;

    my UInt $available = self.cols;
    my UInt $height = self.rows;

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
                @allocs[$i] = (self.cols * $child.sizing.value / 100).floor.UInt min $available;
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
    my UInt $cx = 0;
    my Int $parent-abs-y = self.abs-y;
    my Int $parent-abs-x = self.abs-x;
    for @kids.kv -> $i, $child {
        my UInt $w = @allocs[$i];
        next unless $w > 0;

        if $child.plane {
            $child.reposition(0, $cx);
            $child.handle-resize($height, $w);
        } else {
            $child.init-plane(self.plane, y => 0, x => $cx, rows => $height, cols => $w);
        }
        $child.set-viewport(
            abs-y => $parent-abs-y,
            abs-x => $parent-abs-x + $cx,
            rows  => $height,
            cols  => $w,
        );
        $cx += $w;
    }
}
