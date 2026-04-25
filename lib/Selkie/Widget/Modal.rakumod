=begin pod

=head1 NAME

Selkie::Widget::Modal - Centered overlay dialog with dimmed background

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Modal;
use Selkie::Layout::VBox;
use Selkie::Widget::Button;
use Selkie::Sizing;

my $modal = Selkie::Widget::Modal.new(
    width-ratio    => 0.5,
    height-ratio   => 0.3,
    dim-background => True,
);

my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$content.add: $some-text;
my $ok = Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.fixed(1));
$content.add($ok);
$modal.set-content($content);

$ok.on-press.tap:    -> $ { $app.close-modal };
$modal.on-close.tap: -> $ { $app.close-modal };

$app.show-modal($modal);
$app.focus($ok);

=end code

=head1 DESCRIPTION

A dialog rendered centered on screen, sized as a fraction of the
terminal. The background is dimmed by default so the dialog stands out.
While the modal is active, L<Selkie::App> routes all events through it —
Tab/Shift-Tab still cycle focus within the modal, Esc auto-closes.

For common confirm/cancel dialogs, use L<Selkie::Widget::ConfirmModal>
which wraps Modal with a pre-built button row.

C<set-content(:!destroy)> lets you swap content without destroying the
outgoing widget — useful for multi-step wizards where each step is a
separate content widget.

=head1 EXAMPLES

=head2 Input dialog

=begin code :lang<raku>

my $modal = Selkie::Widget::Modal.new(width-ratio => 0.4, height-ratio => 0.2);
my $body = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$body.add: Selkie::Widget::Text.new(text => 'Rename', sizing => Sizing.fixed(1));
my $input = Selkie::Widget::TextInput.new(sizing => Sizing.fixed(1));
$body.add($input);
$modal.set-content($body);

$input.on-submit.tap: -> $new-name {
    $app.close-modal;
    $app.store.dispatch('rename', :$new-name);
};

$app.show-modal($modal);
$app.focus($input);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::ConfirmModal> — pre-built yes/no confirmation
=item L<Selkie::Widget::FileBrowser> — pre-built file picker
=item L<Selkie::App> — C<show-modal> and C<close-modal> methods

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Event;
use Selkie::Style;

unit class Selkie::Widget::Modal does Selkie::Container;

has Selkie::Widget $!content;
has Rat $.width-ratio = 0.8;
has Rat $.height-ratio = 0.6;
has Bool $.dim-background = True;
has NcplaneHandle $!bg-plane;
has Supplier $!close-supplier = Supplier.new;

method content(--> Selkie::Widget) { $!content }

method on-close(--> Supply) { $!close-supplier.Supply }

method set-content(Selkie::Widget $w, Bool :$destroy = True) {
    # See Border.set-content — same rationale for parking the outgoing
    # plane off-screen when C<:!destroy> is passed. park() recurses
    # through containers and cleans up sprixels on Image widgets.
    if $!content && $destroy {
        $!content.destroy;
    } elsif $!content && $!content.plane {
        $!content.park;
    }
    $!content = $w;
    $w.parent = self;
    self.mark-dirty;
}

method close() {
    $!close-supplier.emit(True);
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

method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!on-resize;
    # Cascade to content sized to the modal's interior (same math as
    # render uses). Propagates synchronously so the content subtree
    # updates before the next render.
    if $!content {
        my UInt $modal-rows = ($rows * $!height-ratio).floor.UInt max 3;
        my UInt $modal-cols = ($cols * $!width-ratio).floor.UInt max 10;
        $!content.handle-resize($modal-rows, $modal-cols);
    }
}

method render() {
    return without self.plane;

    # Calculate modal dimensions based on parent size
    my UInt $parent-rows = self.rows;
    my UInt $parent-cols = self.cols;
    my UInt $modal-rows = ($parent-rows * $!height-ratio).floor.UInt max 3;
    my UInt $modal-cols = ($parent-cols * $!width-ratio).floor.UInt max 10;
    my UInt $modal-y = (($parent-rows - $modal-rows) / 2).floor.UInt;
    my UInt $modal-x = (($parent-cols - $modal-cols) / 2).floor.UInt;

    # Dim background
    if $!dim-background {
        self!render-dim-background($parent-rows, $parent-cols);
    }

    # Position content
    if $!content {
        if $!content.plane {
            $!content.reposition($modal-y, $modal-x);
            $!content.handle-resize($modal-rows, $modal-cols);
        } else {
            $!content.init-plane(self.plane,
                y => $modal-y, x => $modal-x,
                rows => $modal-rows, cols => $modal-cols);
        }
        # Propagate absolute viewport. Neither reposition nor
        # handle-resize updates abs-y / abs-x, and the content's
        # internal layout-children cascade uses self.abs-y as the
        # origin for its children — without this call, every
        # descendant's abs-y stays frozen at its pre-modal value.
        $!content.set-viewport(
            abs-y => self.abs-y + $modal-y,
            abs-x => self.abs-x + $modal-x,
            rows  => $modal-rows,
            cols  => $modal-cols,
        );
        $!content.mark-dirty unless $!content.is-dirty;
        $!content.render;
    }

    self.clear-dirty;
}

method !render-dim-background(UInt $rows, UInt $cols) {
    if $!bg-plane {
        ncplane_move_yx($!bg-plane, 0, 0);
        ncplane_resize_simple($!bg-plane, $rows, $cols);
    } else {
        my $opts = NcplaneOptions.new(y => 0, x => 0, :$rows, :$cols);
        $!bg-plane = ncplane_create(self.plane, $opts);
    }
    return without $!bg-plane;

    ncplane_set_bg_rgb($!bg-plane, 0x000000);
    ncplane_set_fg_rgb($!bg-plane, 0x404040);
    ncplane_erase($!bg-plane);

    my $fill = ' ' x $cols;
    for ^$rows -> $row {
        ncplane_putstr_yx($!bg-plane, $row, 0, $fill);
    }
}

method handle-event(Selkie::Event $ev --> Bool) {
    # Check our own keybinds (e.g., escape to close)
    self!check-keybinds($ev);
}

method destroy() {
    $!content.destroy if $!content;
    $!content = Selkie::Widget;
    if $!bg-plane {
        ncplane_destroy($!bg-plane);
        $!bg-plane = NcplaneHandle;
    }
    self!destroy-plane;
}
