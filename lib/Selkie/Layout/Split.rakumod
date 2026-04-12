use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class Selkie::Layout::Split does Selkie::Container;

has Rat $.ratio = 0.5;
has Str $.orientation = 'horizontal';  # horizontal = left|right, vertical = top|bottom
has NcplaneHandle $!divider-plane;
has Selkie::Widget $.first;
has Selkie::Widget $.second;

method set-first(Selkie::Widget $w --> Selkie::Widget) {
    $!first.destroy if $!first;
    $!first = $w;
    $w.parent = self;
    self.mark-dirty;
    $w;
}

method set-second(Selkie::Widget $w --> Selkie::Widget) {
    $!second.destroy if $!second;
    $!second = $w;
    $w.parent = self;
    self.mark-dirty;
    $w;
}

method render() {
    self!layout-split;
    $!first.render  if $!first  && $!first.is-dirty;
    $!second.render if $!second && $!second.is-dirty;
    self!render-divider;
    self.clear-dirty;
}

method !layout-split() {
    if $!orientation eq 'horizontal' {
        my UInt $total = self.cols;
        my UInt $first-w = ($total * $!ratio).floor.UInt;
        $first-w = $first-w max 1;
        my UInt $divider-x = $first-w;
        my UInt $second-w = $total - $first-w - 1;  # 1 col for divider
        $second-w = $second-w max 0;
        my UInt $h = self.rows;

        self!ensure-child-plane($!first, 0, 0, $h, $first-w) if $!first;
        self!ensure-divider(0, $divider-x, $h, 1);
        self!ensure-child-plane($!second, 0, $divider-x + 1, $h, $second-w) if $!second;
    } else {
        my UInt $total = self.rows;
        my UInt $first-h = ($total * $!ratio).floor.UInt;
        $first-h = $first-h max 1;
        my UInt $divider-y = $first-h;
        my UInt $second-h = $total - $first-h - 1;
        $second-h = $second-h max 0;
        my UInt $w = self.cols;

        self!ensure-child-plane($!first, 0, 0, $first-h, $w) if $!first;
        self!ensure-divider($divider-y, 0, 1, $w);
        self!ensure-child-plane($!second, $divider-y + 1, 0, $second-h, $w) if $!second;
    }
}

method !ensure-child-plane(Selkie::Widget $child, UInt $y, UInt $x, UInt $rows, UInt $cols) {
    if $child.plane {
        $child.reposition($y, $x);
        $child.resize($rows, $cols);
    } else {
        $child.init-plane(self.plane, :$y, :$x, :$rows, :$cols);
    }
    $child.set-viewport(
        abs-y => self.abs-y + $y,
        abs-x => self.abs-x + $x,
        :$rows, :$cols,
    );
}

method !ensure-divider(UInt $y, UInt $x, UInt $rows, UInt $cols) {
    if $!divider-plane {
        ncplane_move_yx($!divider-plane, $y, $x);
        ncplane_resize_simple($!divider-plane, $rows, $cols);
    } else {
        my $opts = NcplaneOptions.new(:$y, :$x, :$rows, :$cols);
        $!divider-plane = ncplane_create(self.plane, $opts);
    }
}

method !render-divider() {
    return without $!divider-plane;
    my $style = self.theme.divider;
    ncplane_set_styles($!divider-plane, $style.styles);
    ncplane_set_fg_rgb($!divider-plane, $style.fg) if $style.fg.defined;
    ncplane_set_bg_rgb($!divider-plane, $style.bg) if $style.bg.defined;
    ncplane_erase($!divider-plane);

    if $!orientation eq 'horizontal' {
        my UInt $h = self.rows;
        for ^$h -> $row {
            ncplane_putstr_yx($!divider-plane, $row, 0, '│');
        }
    } else {
        my UInt $w = self.cols;
        for ^$w -> $col {
            ncplane_putstr_yx($!divider-plane, 0, $col, '─');
        }
    }
}

method focusable-descendants(--> Seq) {
    gather {
        if $!first {
            take $!first if $!first.focusable;
            if $!first ~~ Selkie::Container {
                .take for $!first.focusable-descendants;
            }
        }
        if $!second {
            take $!second if $!second.focusable;
            if $!second ~~ Selkie::Container {
                .take for $!second.focusable-descendants;
            }
        }
    }
}

method destroy() {
    $!first.destroy if $!first;
    $!second.destroy if $!second;
    if $!divider-plane {
        ncplane_destroy($!divider-plane);
        $!divider-plane = NcplaneHandle;
    }
    self!destroy-plane;
}
