use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Widget::Border;
use Selkie::Event;
use Selkie::Sizing;

# A cursor-navigated scrollable list of variable-height widgets.
# Each item has a root widget (renderable), a height, and optionally
# a border (for highlight/clip flags) and a set-clipped method.
#
# The selected item always fully fits in the viewport.
# The item at the opposite end can be partially clipped.

unit class Selkie::Widget::CardList does Selkie::Widget;

has @!items;        # Array of hashes: { widget, root, height, border? }
has Int $!selected = 0;
has Int $!scroll-top = 0;
has Supplier $!select-supplier = Supplier.new;

method new(*%args) {
    %args<focusable> //= True;
    callwith(|%args);
}

method on-select(--> Supply) { $!select-supplier.Supply }
method selected(--> Int) { $!selected }
method count(--> Int) { @!items.elems }

method selected-item() {
    return Nil unless $!selected >= 0 && $!selected < @!items.elems;
    @!items[$!selected]<widget>;
}

# --- Item management ---

method add-item($widget, :$root!, :$height!, :$border) {
    @!items.push({ :$widget, :$root, :$height, :$border });
    self.mark-dirty;
}

method clear-items() {
    for @!items -> %item {
        %item<root>.destroy if %item<root>.plane;
    }
    @!items = ();
    $!selected = 0;
    $!scroll-top = 0;
    self.mark-dirty;
}

method set-item-height(Int $idx, Int $height) {
    return unless $idx >= 0 && $idx < @!items.elems;
    @!items[$idx]<height> = $height;
    self.mark-dirty;
}

# --- Selection ---

method select-index(Int $idx) {
    return unless @!items;
    $!selected = ($idx max 0) min @!items.end;
    self!recalc-scroll;
    self.mark-dirty;
    $!select-supplier.emit($!selected);
}

method select-last() {
    return unless @!items;
    $!selected = @!items.end;
    self!recalc-scroll;
    self.mark-dirty;
}

method select-first() {
    return unless @!items;
    $!selected = 0;
    self!recalc-scroll;
    self.mark-dirty;
}

method scroll-up()   { self!select-prev }
method scroll-down() { self!select-next }

# --- Rendering ---

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $vh = self.rows;
    my UInt $vw = self.cols;
    return self.clear-dirty unless @!items && $vh > 0;

    self!recalc-scroll;

    # Calculate top clip offset
    my $total-to-selected = 0;
    for $!scroll-top .. $!selected -> $i {
        $total-to-selected += @!items[$i]<height>;
    }
    my $top-clip = ($total-to-selected - $vh) max 0;

    # Render items
    my Int $y = 0 - $top-clip;
    my Int $first = $!scroll-top;
    my Int $last = $!scroll-top - 1;

    for $!scroll-top ..^ @!items.elems -> $i {
        my %item = @!items[$i];
        my $h = %item<height>;
        last if $y >= $vh;

        my $visible-top = $y max 0;
        my $visible-bot = ($y + $h) min $vh;
        my $display-h = $visible-bot - $visible-top;

        if $display-h <= 0 {
            $y += $h;
            next;
        }

        my $clipped-top = $y < 0;
        my $clipped-bot = ($y + $h) > $vh;

        # Set border flags if available
        my $border = %item<border>;
        if $border {
            $border.set-has-focus($i == $!selected);
            $border.hide-top-border = $clipped-top;
            $border.hide-bottom-border = $clipped-bot;
        }

        # Notify widget of clipping if it supports it
        my $widget = %item<widget>;
        if $widget.can('set-clipped') {
            $widget.set-clipped(:top($clipped-top), :bottom($clipped-bot));
        }

        my $root = %item<root>;
        if $root.plane {
            $root.reposition($visible-top, 0);
            $root.resize($display-h, $vw);
        } else {
            $root.init-plane(self.plane, y => $visible-top, x => 0,
                rows => $display-h, cols => $vw);
        }
        $root.mark-dirty;
        $root.render;

        $y += $h;
        $last = $i;
    }

    # Move off-screen items out of view
    for ^@!items.elems -> $i {
        next if $i >= $first && $i <= $last;
        my $root = @!items[$i]<root>;
        $root.reposition($vh + 100, 0) if $root.plane;
    }

    self.clear-dirty;
}

# --- Navigation ---

method handle-event(Selkie::Event $ev --> Bool) {
    return True if self!check-keybinds($ev);
    return False unless @!items;

    if $ev.event-type ~~ KeyEvent {
        given $ev.id {
            when NCKEY_UP   { self!select-prev; return True }
            when NCKEY_DOWN { self!select-next; return True }
            when NCKEY_HOME { self.select-first; return True }
            when NCKEY_END  { self.select-last; return True }
        }
    }

    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP   { self!select-prev; return True }
            when NCKEY_SCROLL_DOWN { self!select-next; return True }
        }
    }

    False;
}

method !select-next() {
    return unless @!items;
    if $!selected < @!items.end {
        $!selected++;
        self!recalc-scroll;
        self.mark-dirty;
        $!select-supplier.emit($!selected);
    }
}

method !select-prev() {
    return unless @!items;
    if $!selected > 0 {
        $!selected--;
        self!recalc-scroll;
        self.mark-dirty;
        $!select-supplier.emit($!selected);
    }
}

# --- Scroll calculation ---

method !recalc-scroll() {
    return unless @!items;
    my $vh = self.rows;
    return unless $vh > 0;

    $!selected = ($!selected max 0) min @!items.end;

    if $!selected < $!scroll-top {
        $!scroll-top = $!selected;
        return;
    }

    my $used = 0;
    for $!scroll-top .. $!selected -> $i {
        $used += @!items[$i]<height>;
    }
    return if $used <= $vh;

    my $remaining = $vh;
    my $new-top = $!selected;
    while $new-top > 0 {
        $remaining -= @!items[$new-top]<height>;
        last if $remaining <= 0;
        if @!items[$new-top - 1]<height> <= $remaining {
            $new-top--;
        } else {
            $new-top--;
            last;
        }
    }
    $!scroll-top = $new-top;
}
