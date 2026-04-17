=begin pod

=head1 NAME

Selkie::Layout::Split - Two-pane layout with a divider

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Layout::Split;
use Selkie::Sizing;

my $split = Selkie::Layout::Split.new(
    orientation => 'horizontal',   # left | right
    ratio       => 0.3,            # 30% | 70%
    sizing      => Sizing.flex,
);
$split.set-first($sidebar);
$split.set-second($main);

=end code

=head1 DESCRIPTION

Split divides its area into exactly two panes with a one-cell divider
between them. The C<ratio> attribute controls the split — C<0.3> means
the first pane takes 30% of the space, the second gets the rest (minus
one cell for the divider).

Two orientations:

=item C<'horizontal'> — left and right panes, divided by a vertical bar
=item C<'vertical'> — top and bottom panes, divided by a horizontal bar

Unlike VBox/HBox which take a list of children, Split takes exactly two
content widgets via C<set-first> and C<set-second>. Each assignment
destroys the previous occupant of that slot — use a container widget
(like another VBox) on each side if you need more than one widget per
pane.

=head1 EXAMPLES

=head2 Sidebar + main content

A classic two-pane layout with a 25/75 split:

=begin code :lang<raku>

my $split = Selkie::Layout::Split.new(
    orientation => 'horizontal',
    ratio       => 0.25,
    sizing      => Sizing.flex,
);
$split.set-first($sidebar-list);
$split.set-second($detail-view);

=end code

=head2 Editor + preview (vertical split)

Top half is the editor, bottom half is the live preview:

=begin code :lang<raku>

my $split = Selkie::Layout::Split.new(
    orientation => 'vertical',
    ratio       => 0.5,
    sizing      => Sizing.flex,
);
$split.set-first($editor);
$split.set-second($preview);

=end code

=head2 Multiple widgets per pane

Wrap each side in its own layout:

=begin code :lang<raku>

my $left = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$left.add($search-input);     # fixed(1)
$left.add($result-list);      # flex

$split.set-first($left);
$split.set-second($details);

=end code

=head1 SEE ALSO

=item L<Selkie::Layout::VBox>, L<Selkie::Layout::HBox> — N-child stacked layouts
=item L<Selkie::Theme> — C<divider> slot controls divider appearance

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Sizing;

unit class Selkie::Layout::Split does Selkie::Container;

#| The fraction of space given to the first pane. C<0.5> is an even
#| split; C<0.3> gives 30% to the first pane, 70% to the second. Can
#| be changed at runtime — just mark the Split dirty and re-layout.
has Rat $.ratio = 0.5;

#| Either C<'horizontal'> (left+right panes, vertical divider) or
#| C<'vertical'> (top+bottom panes, horizontal divider).
has Str $.orientation = 'horizontal';

has NcplaneHandle $!divider-plane;

#| The first (left or top) pane's widget. Set via C<set-first>.
has Selkie::Widget $.first;

#| The second (right or bottom) pane's widget. Set via C<set-second>.
has Selkie::Widget $.second;

#|( Install a widget in the first pane. The previous occupant (if any)
    is destroyed. Returns the new widget for chaining. )
method set-first(Selkie::Widget $w --> Selkie::Widget) {
    $!first.destroy if $!first;
    $!first = $w;
    $w.parent = self;
    self.mark-dirty;
    $w;
}

#|( Install a widget in the second pane. The previous occupant is
    destroyed. Returns the new widget for chaining. )
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

method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
    self!layout-split if self.plane;
}

method !layout-split() {
    if $!orientation eq 'horizontal' {
        my UInt $total = self.cols;
        my UInt $first-w = ($total * $!ratio).floor.UInt;
        $first-w = $first-w max 1;
        my UInt $divider-x = $first-w;
        my UInt $second-w = $total - $first-w - 1;
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
        $child.handle-resize($rows, $cols);
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

#|( Expose the panes as `children` so that Container-level cascade
    helpers (notably `!unsubscribe-tree`) reach them. Split stores its
    panes in `$!first` / `$!second` rather than the inherited
    `@!children` array, so without this override the cascade walks
    an empty list and leaks subscriptions / bookkeeping for anything
    inside a pane. )
method children(--> List) {
    ($!first, $!second).grep(*.defined).List;
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
