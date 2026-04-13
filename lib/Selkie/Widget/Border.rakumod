=begin pod

=head1 NAME

Selkie::Widget::Border - Decorative frame around a single content widget

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Border;
use Selkie::Sizing;

my $border = Selkie::Widget::Border.new(
    title  => 'Characters',
    sizing => Sizing.fixed(20),
);
$border.set-content($avatar-list);

=end code

=head1 DESCRIPTION

Draws a box around a single child widget. Auto-highlights when any
descendant has focus (via a store subscription on C<ui.focused-widget>
— it's the canonical example of the "widget reacts to store state"
pattern).

Requires at least 3x3 dimensions. Redraws its edges after content renders
to cover pixel bleed from image blits — useful when wrapping an Image.

=head2 Swapping content

By default, C<set-content> destroys the outgoing widget. Pass
C<:!destroy> to swap while keeping the old widget alive — useful for
tab-style panes that cycle through persistent views:

=begin code :lang<raku>

$border.set-content($view-a);
$border.set-content($view-b, :!destroy);    # $view-a survives
$border.set-content($view-a, :!destroy);    # swap back, still intact

=end code

=head1 EXAMPLES

=head2 Named panels

=begin code :lang<raku>

my $left = Selkie::Widget::Border.new(
    title  => 'Characters',
    sizing => Sizing.fixed(20),
);
$left.set-content($char-list);

my $right = Selkie::Widget::Border.new(
    title  => 'Chat',
    sizing => Sizing.flex,
);
$right.set-content($chat-view);

=end code

=head2 Stacking borders

Use C<hide-top-border> / C<hide-bottom-border> to share edges between
adjacent panels:

=begin code :lang<raku>

$top-panel.hide-bottom-border    = True;
$bottom-panel.hide-top-border    = True;

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Modal> — centered overlay; also has C<set-content(:!destroy)>
=item L<Selkie::Theme> — C<border> / C<border-focused> slots control appearance

=end pod

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

method content(--> Selkie::Widget) { $!content }

method set-content(Selkie::Widget $w, Bool :$destroy = True) {
    # Destroying the outgoing content is the safe default — most callers
    # won't reuse it. Pass :!destroy when swapping between widgets that
    # you want to keep alive (e.g. a tab-style pane that cycles through
    # several persistent views).
    #
    # In the non-destroy case we park the outgoing plane far off-screen
    # so its last-rendered contents don't bleed through behind the new
    # content. Widget state (plane, subscriptions, cursor positions) is
    # preserved, and C<reposition> puts it back in place on the next
    # install. Values > screen height are safe — notcurses tolerates
    # out-of-bounds plane positions and simply clips them.
    if $!content && $destroy {
        $!content.destroy;
    } elsif $!content && $!content.plane {
        $!content.reposition(10_000, 0);
    }
    $!content = $w;
    $w.parent = self;
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

# Auto-subscribe to focus state when store becomes available. `once-*`
# variants are idempotent — reparenting and repeated set-store calls
# won't create duplicate subscriptions.
method on-store-attached($store) {
    my $border = self;
    self.once-subscribe-computed("border-focus-{self.WHICH}", -> $s {
        my $focused = $s.get-in('ui', 'focused-widget');
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

method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
    # Cascade to wrapped content so its subtree also re-sizes now.
    # Inner dims exclude the border frame.
    if $!content {
        my $inner-rows = ($rows - 2) max 0;
        my $inner-cols = ($cols - 2) max 0;
        $!content.handle-resize($inner-rows.UInt, $inner-cols.UInt);
    }
}

method render() {
    return without self.plane;

    # Update focus state directly from the store on each render. Cheap and
    # avoids stale state if the subscription-driven update hasn't landed yet.
    if self.store {
        my $focused = self.store.get-in('ui', 'focused-widget');
        $!has-focus = $focused.defined && self!is-descendant($focused);
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
                $!content.handle-resize($inner-rows, $inner-cols);
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
