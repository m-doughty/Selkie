use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::Border does Selkie::Container;

has Selkie::Widget $!content;
has Str $.title = '';
has Bool $!has-focus = False;
has Bool $.hide-top-border is rw = False;
has Bool $.hide-bottom-border is rw = False;
has Bool $!auto-focus-subscribed = False;

method content(--> Selkie::Widget) { $!content }

method set-content(Selkie::Widget $w) {
    $!content.destroy if $!content;
    $!content = $w;
    $w.parent = self;
    # Propagate store to content
    $w.set-store(self.store) if self.store;
    self.mark-dirty;
}

method set-title(Str:D $t) {
    $!title = $t;
    self.mark-dirty;
}

method set-has-focus(Bool $f) {
    return if $f == $!has-focus;
    $!has-focus = $f;
    self.mark-dirty;
}

method has-focus(--> Bool) { $!has-focus }

# Auto-subscribe to focus state when store becomes available
method on-store-attached($store) {
    self!setup-focus-subscription unless $!auto-focus-subscribed;
}

method !setup-focus-subscription() {
    return without self.store;
    $!auto-focus-subscribed = True;

    my $border = self;
    self.subscribe-computed("border-focus-{self.WHICH}", -> $store {
        my $focused = $store.get-in('ui', 'focused-widget');
        $focused.defined ?? $border!is-descendant($focused) !! False;
    });
}

method !is-descendant(Selkie::Widget $widget --> Bool) {
    # Walk up from widget to see if we're an ancestor
    my $w = $widget;
    while $w.defined {
        return True if $w === $!content;
        return True if $w.parent.defined && $w.parent === self;
        $w = $w.parent;
    }
    False;
}

method render() {
    return without self.plane;

    # Update focus state from store if subscribed
    if $!auto-focus-subscribed && self.store {
        my $focused = self.store.get-in('ui', 'focused-widget');
        my $should-focus = $focused.defined && self!is-descendant($focused);
        $!has-focus = $should-focus;
    }

    my UInt $rows = self.rows;
    my UInt $cols = self.cols;
    return if $rows < 3 || $cols < 3;

    my $border-style = $!has-focus ?? self.theme.border-focused !! self.theme.border;
    self.apply-style($border-style);
    ncplane_erase(self.plane);

    # Draw border
    my UInt $top-y = 0;
    my UInt $bot-y = $rows - 1;
    my UInt $content-top = $!hide-top-border ?? 0 !! 1;
    my UInt $content-bot = $!hide-bottom-border ?? $rows !! $rows - 1;

    unless $!hide-top-border {
        ncplane_putstr_yx(self.plane, $top-y, 0, '┌');
        ncplane_putstr_yx(self.plane, $top-y, $cols - 1, '┐');
        for 1 ..^ ($cols - 1) -> $x {
            ncplane_putstr_yx(self.plane, $top-y, $x, '─');
        }
    }

    unless $!hide-bottom-border {
        ncplane_putstr_yx(self.plane, $bot-y, 0, '└');
        ncplane_putstr_yx(self.plane, $bot-y, $cols - 1, '┘');
        for 1 ..^ ($cols - 1) -> $x {
            ncplane_putstr_yx(self.plane, $bot-y, $x, '─');
        }
    }

    for $content-top ..^ $content-bot -> $y {
        ncplane_putstr_yx(self.plane, $y, 0, '│');
        ncplane_putstr_yx(self.plane, $y, $cols - 1, '│');
    }

    # Draw title in top border
    if !$!hide-top-border && $!title.chars > 0 && $cols > 4 {
        my $display = $!title.substr(0, $cols - 4);
        ncplane_putstr_yx(self.plane, 0, 2, " $display ");
    }

    # Position and render content inside the border
    if $!content {
        my UInt $inner-top = $content-top;
        my UInt $inner-rows = $content-bot - $content-top;
        my UInt $inner-cols = $cols - 2;
        if $inner-rows > 0 {
            if $!content.plane {
                $!content.reposition($inner-top, 1);
                $!content.resize($inner-rows, $inner-cols);
            } else {
                $!content.init-plane(self.plane,
                    y => $inner-top, x => 1, rows => $inner-rows, cols => $inner-cols);
            }
            $!content.set-viewport(
                abs-y => self.abs-y + $inner-top,
                abs-x => self.abs-x + 1,
                rows  => $inner-rows,
                cols  => $inner-cols,
            );
            $!content.mark-dirty unless $!content.is-dirty;
            $!content.render;
        }
    }

    # Redraw border edges after content render to cover any pixel bleed
    self.apply-style($border-style);
    for $content-top ..^ $content-bot -> $y {
        ncplane_putstr_yx(self.plane, $y, 0, '│');
        ncplane_putstr_yx(self.plane, $y, $cols - 1, '│');
    }
    unless $!hide-bottom-border {
        ncplane_putstr_yx(self.plane, $bot-y, 0, '└');
        ncplane_putstr_yx(self.plane, $bot-y, $cols - 1, '┘');
        for 1 ..^ ($cols - 1) -> $x {
            ncplane_putstr_yx(self.plane, $bot-y, $x, '─');
        }
    }

    self.clear-dirty;
}

method focusable-descendants(--> Seq) {
    return ().Seq without $!content;
    gather {
        take $!content if $!content.focusable;
        if $!content ~~ Selkie::Container {
            .take for $!content.focusable-descendants;
        }
    }
}

method destroy() {
    $!content.destroy if $!content;
    $!content = Selkie::Widget;
    self!destroy-plane;
}
