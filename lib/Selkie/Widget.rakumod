unit role Selkie::Widget;

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Channel;

use Selkie::Style;
use Selkie::Theme;
use Selkie::Event;
use Selkie::Sizing;

my atomicint $next-widget-id = 0;

has Int $.widget-id = ++⚛$next-widget-id;
has NcplaneHandle $!plane;
has Bool $!owns-plane = True;
has Selkie::Widget $.parent is rw;
has Bool $!dirty = True;
has Bool $!mounted = False;
has UInt $!rows = 0;
has UInt $!cols = 0;
has UInt $!y = 0;
has UInt $!x = 0;
# Viewport: absolute position and visible bounds, set by parent layout
has Int $!abs-y = 0;
has Int $!abs-x = 0;
has UInt $!viewport-rows = 0;
has UInt $!viewport-cols = 0;
has Sizing $.sizing = Sizing.flex;
has Bool $.focusable = False;
has Selkie::Theme $!theme;
has @!keybinds;
has $!store;     # Selkie::Store — untyped to avoid circular import

method plane(--> NcplaneHandle) { $!plane }
method rows(--> UInt) { $!rows }
method cols(--> UInt) { $!cols }
method y(--> UInt) { $!y }
method x(--> UInt) { $!x }
method is-dirty(--> Bool) { $!dirty }

# Viewport: absolute position and available space as set by parent
method abs-y(--> Int) { $!abs-y }
method abs-x(--> Int) { $!abs-x }
method viewport-rows(--> UInt) { $!viewport-rows }
method viewport-cols(--> UInt) { $!viewport-cols }

method set-viewport(Int :$abs-y!, Int :$abs-x!, UInt :$rows!, UInt :$cols!) {
    $!abs-y = $abs-y;
    $!abs-x = $abs-x;
    $!viewport-rows = $rows;
    $!viewport-cols = $cols;
}

method theme(--> Selkie::Theme) {
    $!theme // ($!parent andthen .theme) // Selkie::Theme.default;
}

method set-theme(Selkie::Theme $t) {
    $!theme = $t;
    self.mark-dirty;
}

# --- Private helpers (accessible to composed roles/classes) ---

method !apply-resize(UInt $rows, UInt $cols) {
    ncplane_resize_simple($!plane, $rows, $cols) if $!plane;
    $!rows = $rows;
    $!cols = $cols;
}

method !destroy-plane() {
    if $!plane && $!owns-plane {
        ncplane_destroy($!plane);
    }
    $!plane = NcplaneHandle;
}

method !set-sizing(Sizing $s) {
    $!sizing = $s;
}

# --- Store integration ---

method store() { $!store }

method set-store($store) {
    $!store = $store;
    # Propagate to children (Container) and content (Border/Modal)
    if self.can('children') {
        for self.children -> $child {
            $child.set-store($store);
        }
    }
    if self.can('content') {
        my $c = self.content;
        $c.set-store($store) if $c.defined;
    }
    self.on-store-attached($store) if self.can('on-store-attached');
}

method dispatch(Str:D $event, *%payload) {
    $!store.dispatch($event, |%payload) if $!store;
}

method subscribe(Str:D $id, *@path) {
    $!store.subscribe($id, @path, self) if $!store;
}

method subscribe-computed(Str:D $id, &compute) {
    $!store.subscribe-computed($id, &compute, self) if $!store;
}

method update-sizing(Sizing $s) {
    $!sizing = $s;
    self.mark-dirty;
    $!parent.mark-dirty if $!parent.defined;
}

# --- Framework-internal methods (public for cross-widget access) ---

method init-plane(NcplaneHandle $parent-plane, UInt :$y = 0, UInt :$x = 0,
                  UInt :$rows = 1, UInt :$cols = 1) {
    my $opts = NcplaneOptions.new(:$y, :$x, :$rows, :$cols);
    $!plane = ncplane_create($parent-plane, $opts);
    die "Failed to create plane" without $!plane;
    $!rows = $rows;
    $!cols = $cols;
    $!y = $y;
    $!x = $x;
}

method adopt-plane(NcplaneHandle $plane, UInt :$rows, UInt :$cols) {
    $!plane = $plane;
    $!owns-plane = False;
    $!rows = $rows;
    $!cols = $cols;
    $!y = 0;
    $!x = 0;
}

method mark-dirty() {
    return if $!dirty;
    $!dirty = True;
    $!parent.mark-dirty if $!parent.defined;
}

method clear-dirty() {
    $!dirty = False;
}

method apply-style(Selkie::Style $style) {
    ncplane_set_styles($!plane, $style.styles);
    ncplane_set_fg_rgb($!plane, $style.fg) if $style.fg.defined;
    ncplane_set_bg_rgb($!plane, $style.bg) if $style.bg.defined;
}

# --- Public API ---

method resize(UInt $rows, UInt $cols) {
    return if $rows == $!rows && $cols == $!cols;
    self!apply-resize($rows, $cols);
    self.mark-dirty;
}

method reposition(UInt $y, UInt $x) {
    return if $y == $!y && $x == $!x;
    ncplane_move_yx($!plane, $y, $x) if $!plane;
    $!y = $y;
    $!x = $x;
}

method render() { ... }

method on-key(Str:D $spec, &handler) {
    @!keybinds.push: Keybind.parse($spec, &handler);
}

method !check-keybinds(Selkie::Event $ev --> Bool) {
    for @!keybinds -> $kb {
        if $kb.matches($ev) {
            $kb.handler.($ev);
            return True;
        }
    }
    False;
}

method handle-event(Selkie::Event $ev --> Bool) {
    self!check-keybinds($ev);
}

method destroy() {
    self!destroy-plane;
}

method DESTROY() {
    self.destroy;
}
