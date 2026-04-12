use Notcurses::Native;
use Notcurses::Native::Types;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class Selkie::Layout::HBox does Selkie::Container;

method render() {
    self!layout-children;
    self!render-children;
    self.clear-dirty;
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
            $child.resize($height, $w);
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
