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

method set-content(Selkie::Widget $w) {
    $!content.destroy if $!content;
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
            $!content.resize($modal-rows, $modal-cols);
        } else {
            $!content.init-plane(self.plane,
                y => $modal-y, x => $modal-x,
                rows => $modal-rows, cols => $modal-cols);
        }
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
