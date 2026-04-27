=begin pod

=head1 NAME

Selkie::Widget - Base role composed by every Selkie widget

=head1 SYNOPSIS

A minimal custom widget that renders a fixed string:

=begin code :lang<raku>

use Notcurses::Native;
use Notcurses::Native::Plane;
use Selkie::Widget;

unit class My::Hello does Selkie::Widget;

method render() {
    return without self.plane;
    ncplane_erase(self.plane);
    self.apply-style(self.theme.text);
    ncplane_putstr_yx(self.plane, 0, 0, 'Hello, Selkie!');
    self.clear-dirty;
}

=end code

Add it to any layout and it just works:

=begin code :lang<raku>

use Selkie::Sizing;

$vbox.add: My::Hello.new(sizing => Sizing.fixed(1));

=end code

=head1 DESCRIPTION

C<Selkie::Widget> is the role at the bottom of every widget in the
framework. Compose it to create your own widget; Selkie handles the tree
integration, rendering cycle, focus routing, theme inheritance, store
plumbing, and memory management.

You almost never construct a C<Selkie::Widget> directly — it's a role,
so you C<does Selkie::Widget> on your own class. The framework itself
composes it to build every built-in widget (C<Text>, C<Button>,
C<ListView>, and so on).

=head2 What you get for free

=item A notcurses plane to render into, created and destroyed for you
=item Theme inheritance from the widget tree
=item Themed plane-base painting so erase / unwritten cells show the theme background rather than the terminal default — applied on C<init-plane>, C<set-store>, and C<set-theme>
=item Keybind registration and event bubbling
=item Dirty tracking so your C<render> method only runs when needed
=item Per-widget subscription to the reactive store
=item Clean shutdown when the widget goes out of scope

=head2 What you must provide

At minimum, a C<render> method. That's it.

=head2 What you may provide

=item C<handle-event> — to react to keyboard or mouse input when focused
=item C<on-store-attached> — to wire up subscriptions when the store appears
=item C<destroy> — to clean up anything beyond the plane (e.g. extra
notcurses handles, file descriptors, subscriptions)

=head1 LIFECYCLE

Construction happens in normal Raku fashion: C<My::Widget.new(...)>. At
this point the widget has no plane and no size. It's safe to store
configuration on the object but not to call notcurses functions.

When the widget is added to a parent layout (via C<$parent.add($child)>),
the parent calls C<init-plane> to create a notcurses plane sized to its
share of the layout. After this point C<self.plane> returns a valid
handle, and C<self.rows> / C<self.cols> reflect the plane's dimensions.

Each frame, the framework walks the tree and calls C<render> on any
widget whose C<is-dirty> is true. Your render method should:

=item Erase the plane with C<ncplane_erase(self.plane)>
=item Apply styles with C<self.apply-style($style)>
=item Write to the plane with notcurses calls
=item Call C<self.clear-dirty> at the end

When the widget is removed or the program exits, C<destroy> is called
and the plane is freed.

=head1 OVERRIDE POINTS

The public API is organised into three buckets.

=head2 Required override

=item C<render> — draw yourself onto C<self.plane>. Must be defined by the composing class.

=head2 Optional overrides

=item C<handle-event($ev --> Bool)> — return True if you consumed the event
=item C<destroy> — call C<self.destroy-plane> and clean up any extras
=item C<on-store-attached($store)> — implement this (no inherited default) to register subscriptions

=head2 Do not override

=item C<init-plane>, C<adopt-plane> — called by layout containers
=item C<mark-dirty>, C<clear-dirty> — called by the render cycle
=item C<set-viewport> — called by parent layouts

=head1 EXAMPLES

=head2 Example 1 — A static colored bar

The simplest useful widget. A solid block of color spanning its full
size. Good for spacers or visual dividers.

=begin code :lang<raku>

use Notcurses::Native;
use Notcurses::Native::Plane;
use Selkie::Widget;

unit class My::ColorBar does Selkie::Widget;

has UInt $.color is required;   # 0xRRGGBB

method render() {
    return without self.plane;
    ncplane_set_bg_rgb(self.plane, $!color);
    ncplane_erase(self.plane);
    self.clear-dirty;
}

=end code

Use it like:

=begin code :lang<raku>

$vbox.add: My::ColorBar.new(color => 0xFF5555, sizing => Sizing.fixed(1));

=end code

=head2 Example 2 — A focusable toggle that emits on change

A box that flips a boolean when the user presses Space or Enter. The
state is owned by the widget; interested app code subscribes by tapping
the C<on-toggle> Supply. This is the canonical leaf-widget pattern in
Selkie — widgets emit, app code dispatches to the store.

=begin code :lang<raku>

use Notcurses::Native;
use Notcurses::Native::Plane;
use Notcurses::Native::Types;
use Selkie::Widget;
use Selkie::Event;

unit class My::Toggle does Selkie::Widget;

has Bool $.state = False;
has Supplier $!toggle-supplier = Supplier.new;

method new(*%args --> My::Toggle) {
    # Focusable by default, so Tab can reach us
    %args<focusable> //= True;
    callwith(|%args);
}

method on-toggle(--> Supply) { $!toggle-supplier.Supply }

method toggle() {
    $!state = !$!state;
    $!toggle-supplier.emit($!state);
    self.mark-dirty;
}

method render() {
    return without self.plane;
    my $style = self.theme.text;
    self.apply-style($style);
    ncplane_erase(self.plane);
    my $glyph = $!state ?? '●' !! '○';
    ncplane_putstr_yx(self.plane, 0, 0, $glyph);
    self.clear-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    # Only respond when we have focus — the app routes events to the
    # focused widget and up the parent chain.
    return False unless $ev.event-type ~~ KeyEvent;
    if $ev.id == NCKEY_ENTER || $ev.id == NCKEY_SPACE {
        self.toggle;
        return True;
    }
    # Pass through to any registered custom keybinds
    self!check-keybinds($ev);
}

=end code

Consuming app code:

=begin code :lang<raku>

my $toggle = My::Toggle.new(sizing => Sizing.fixed(1));
$vbox.add($toggle);
$toggle.on-toggle.tap: -> Bool $on {
    # Tap fires whenever state flips. Dispatch to the store from here.
    $app.store.dispatch('setting/changed', value => $on);
};

=end code

=head2 Example 3 — Registering a custom keybind

Widgets can register per-instance keybinds with C<on-key>. These fire
when the widget is focused (or, if unfocused, are available for the
parent chain to delegate to). Useful for shortcuts scoped to a specific
view.

=begin code :lang<raku>

my $list-view = Selkie::Widget::ListView.new(sizing => Sizing.flex);

# 'a' on the list triggers "add"
$list-view.on-key: 'a', -> $ {
    open-add-dialog();
};

# 'd' with the list focused deletes the cursor item
$list-view.on-key: 'd', -> $ {
    delete-current-item();
};

=end code

Keybinds with a modifier (C<ctrl+>, C<alt+>, C<super+>) work even when
a text input is focused — the input lets modified keys bubble up. Bare
character keybinds get consumed by text inputs, so reserve them for
list-style widgets.

=head2 Example 4 — A widget that reacts to store state

When a widget's appearance depends on shared application state, subscribe
to the store from C<on-store-attached>. The framework calls this once
per C<set-store> call, so use C<once-subscribe> / C<once-subscribe-computed>
to avoid duplicate registrations across repeated calls.

=begin code :lang<raku>

use Selkie::Widget;

unit class My::UnreadBadge does Selkie::Widget;

has UInt $!count = 0;

method on-store-attached($store) {
    # Idempotent: won't double-register if on-store-attached is called
    # again (e.g. if this widget is reparented).
    self.once-subscribe-computed('unread-count', -> $s {
        $s.get-in('inbox', 'unread') // 0;
    });
}

method render() {
    return without self.plane;
    # Re-read fresh from the store each render; the subscription just
    # ensures we're re-rendered when the value changes.
    $!count = self.store.get-in('inbox', 'unread') // 0 if self.store;
    my $style = self.theme.text-highlight;
    self.apply-style($style);
    ncplane_erase(self.plane);
    my $badge = $!count > 0 ?? "($!count)" !! '';
    ncplane_putstr_yx(self.plane, 0, 0, $badge);
    self.clear-dirty;
}

=end code

=head1 SEE ALSO

=item L<Selkie::Container> — for widgets that hold children
=item L<Selkie::Sizing> — the fixed/percent/flex sizing model
=item L<Selkie::Theme> and L<Selkie::Style> — styling inherited through the tree
=item L<Selkie::Event> — the keyboard/mouse event abstraction
=item L<Selkie::Store> — the reactive state store

=end pod

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

#| A monotonically-increasing integer identifier unique to each widget
#| instance. Assigned at construction and never changes. Useful as a
#| key when you need identity-stable references in subscriptions or
#| debug output.
has Int $.widget-id = ++⚛$next-widget-id;

has NcplaneHandle $!plane;
has Bool $!owns-plane = True;

#| The containing widget, set by the parent layout when this widget is
#| added to it. Read-only in practice — layouts manage this — but exposed
#| as C<is rw> so internal helpers can reparent.
has Selkie::Widget $.parent is rw;

has Bool $!dirty = True;
has Bool $!mounted = False;
has UInt $!rows = 0;
has UInt $!cols = 0;
has UInt $!y = 0;
has UInt $!x = 0;
has Int $!abs-y = 0;
has Int $!abs-x = 0;
has UInt $!viewport-rows = 0;
has UInt $!viewport-cols = 0;

#| How this widget wants to be sized by its parent layout. See
#| L<Selkie::Sizing>: C<Sizing.fixed($n)>, C<Sizing.percent($n)>, or
#| C<Sizing.flex($n = 1)>. Defaults to C<Sizing.flex>.
has Sizing $.sizing = Sizing.flex;

#| Whether this widget can receive focus via Tab / Shift-Tab cycling or
#| direct C<$app.focus($widget)> calls. Leaf input widgets typically
#| override this to True in their C<new> method:
#|
#|     method new(*%args) {
#|         %args<focusable> //= True;
#|         callwith(|%args);
#|     }
has Bool $.focusable = False;

has Selkie::Theme $!theme;
has @!keybinds;
has $!store;     # Selkie::Store — untyped to avoid circular import

#|( Returns the notcurses plane this widget renders to, or the type
    object C<NcplaneHandle> if the widget has not been added to a
    parent yet. Always guard with C<return without self.plane;> at the
    top of C<render>. )
method plane(--> NcplaneHandle) { $!plane }

#| Current row height of the widget's plane.
method rows(--> UInt) { $!rows }

#| Current column width of the widget's plane.
method cols(--> UInt) { $!cols }

#| Y offset relative to the parent plane.
method y(--> UInt) { $!y }

#| X offset relative to the parent plane.
method x(--> UInt) { $!x }

#| True if this widget needs to be re-rendered on the next frame.
method is-dirty(--> Bool) { $!dirty }

#| Absolute Y position on the screen — the parent layout computes this
#| by accumulating its own C<abs-y> with this widget's local offset.
#| Useful for overlay positioning.
method abs-y(--> Int) { $!abs-y }

#| Absolute X position on the screen. See C<abs-y>.
method abs-x(--> Int) { $!abs-x }

#| Number of rows actually visible on screen — may be smaller than
#| C<rows> if a parent ScrollView is clipping us.
method viewport-rows(--> UInt) { $!viewport-rows }

#| Number of columns actually visible on screen. See C<viewport-rows>.
method viewport-cols(--> UInt) { $!viewport-cols }

#|( Called by parent layouts during layout. Propagates absolute screen
    position and visible bounds to this widget. You don't call this
    yourself unless you're implementing a layout container.

    Marks the widget dirty when its absolute position changes. Most
    widgets render position-independent cells, so this is redundant for
    them — but Image needs it: notcurses sprixels don't follow plane
    moves, and Image's blit-plane teardown only happens inside its
    C<render>. If a parent shifts a card around (CardList scroll, screen
    layout reflow) without independently dirtying the subtree, the
    Image's render won't fire and the sprixel ghosts at the old screen
    coordinates. Marking dirty here ensures the next pass re-runs every
    affected widget; Image's cache check then short-circuits the
    re-blit when its own state didn't change. )
method set-viewport(Int :$abs-y!, Int :$abs-x!, UInt :$rows!, UInt :$cols!) {
    # The dirty-on-position-change check (added in 0.4.6 for the
    # Image avatar-ghost fix) is delegated to a free sub rather than
    # written inline. Inlined boxed-Int `!=` here triggered a MoarVM
    # spesh mis-specialisation on this hot path — once the render
    # loop had warmed spesh statistics on this method, a later call
    # crashed with "P6opaque: get_boxed_ref could not unbox for the
    # representation 'P6bigint' of type Scalar" pointed at this
    # method's signature line.
    #
    # Routing through a free sub with native-int parameters gives
    # spesh a fresh, simpler frame to specialise; the boxed-Int
    # comparison candidate that was being mis-specialised never
    # appears. Screen coordinates are always well within int64 so
    # the coercion at the call site is loss-free.
    my $moved = position-changed($abs-y, $abs-x, $!abs-y, $!abs-x);
    $!abs-y = $abs-y;
    $!abs-x = $abs-x;
    $!viewport-rows = $rows;
    $!viewport-cols = $cols;
    self.mark-dirty if $moved;
}

# Native-int comparison helper, kept as a free sub so spesh sees a
# clean specialisation target. See `set-viewport` for the rationale.
sub position-changed(int $new-y, int $new-x, int $old-y, int $old-x --> Bool) {
    $new-y != $old-y || $new-x != $old-x;
}

#|( The effective theme for this widget. Walks up the parent chain until
    it finds a widget with an explicit theme, falling back to
    C<Selkie::Theme.default>. Use this in C<render> rather than caching
    a theme reference, so theme changes propagate correctly. )
method theme(--> Selkie::Theme) {
    $!theme // ($!parent andthen .theme) // Selkie::Theme.default;
}

#|( Override the theme for this widget and its subtree. Repaints this
    widget's plane base, marks it dirty, then recurses into C<.children>
    and C<.content> so every descendant's plane base is repainted too.

    The recursion matters: C<ncplane_erase> on a child plane fills with
    that child's base cell, which was set the first time C<set-theme>
    or C<set-store> ran on it. Without the cascade here, only the root
    on which the caller invoked C<set-theme> would repaint, and any
    cell a descendant didn't explicitly write would keep showing the
    OLD theme background — the visible symptom is "I changed theme
    and the tab bar / hint footer kept the old colour".

    Equivalent shape to C<set-store> just below — same C<self.can>
    detection so containers (children) and decorators (content) are
    both reached without coupling C<Widget> to either role. )
method set-theme(Selkie::Theme $t) {
    $!theme = $t;
    self!sync-plane-base;
    self.mark-dirty;
    if self.can('children') {
        for self.children -> $child {
            $child.set-theme($t);
        }
    }
    if self.can('content') {
        my $c = self.content;
        $c.set-theme($t) if $c.defined;
    }
}

#|( Paint this widget's plane base cell using the active theme's
    `base` style so `ncplane_erase` and any cell the widget doesn't
    explicitly write will carry the theme's background / foreground
    rather than notcurses's default-empty state (which renders as
    the terminal's own default). Safe to call repeatedly and before
    the plane or theme are ready — no-op in those cases. )
method !sync-plane-base() {
    return without $!plane;
    my $theme = self.theme;
    return without $theme.defined;
    my $base = $theme.base;
    return without $base.defined;
    my uint64 $channels = 0;
    ncchannels_set_fg_rgb($channels, $base.fg) if $base.fg.defined;
    ncchannels_set_bg_rgb($channels, $base.bg) if $base.bg.defined;
    ncplane_set_base($!plane, ' ', 0, $channels);
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

#|( Replace the widget's sizing constraint after construction. The
    parent layout picks up the new value on its next reflow. Useful
    for conditional UI — a form field that should disappear under
    one mode can be set to C<Sizing.fixed(0)> to collapse out of the
    flow without removing it from the widget tree. Subclasses with
    height-driven content (e.g. C<MultiLineInput> growing as the user
    types) call this from inside their own re-measure logic. )
method set-sizing(Sizing $s) {
    $!sizing = $s;
}

# --- Store integration ---

#| The L<Selkie::Store> attached to this widget, or C<Nil> if no store
#| has been set yet. Propagates automatically from parent to child.
method store() { $!store }

#|( Attach a store to this widget. Called automatically by parent
    containers when a widget is added to the tree and a store exists.
    Recursively propagates to children and Border/Modal content. Fires
    C<on-store-attached> on the widget if implemented. You shouldn't
    need to call this directly — just add the widget to a tree that
    has a store. )
method set-store($store) {
    $!store = $store;
    if self.can('children') {
        for self.children -> $child {
            $child.set-store($store);
        }
    }
    if self.can('content') {
        my $c = self.content;
        $c.set-store($store) if $c.defined;
    }
    # Once the store (and with it the ancestral theme chain) is attached,
    # re-paint the plane base so themes that only became resolvable at
    # this point take effect. Runs once per set-store, not per render.
    self!sync-plane-base;
    self.on-store-attached($store) if self.can('on-store-attached');
}

#|( Convenience for dispatching a store event. Equivalent to
    C<self.store.dispatch($event, |%payload)> but gracefully no-ops if
    no store is attached. Most widgets shouldn't dispatch directly —
    prefer emitting on a Supply and letting app code dispatch. )
method dispatch(Str:D $event, *%payload) {
    $!store.dispatch($event, |%payload) if $!store;
}

#|( Subscribe this widget to a path in the store. When the value at
    that path changes, the widget is marked dirty and re-renders. See
    L<Selkie::Store> for details. Typically called from
    C<on-store-attached>. )
method subscribe(Str:D $id, *@path) {
    $!store.subscribe($id, @path, self) if $!store;
}

#|( Subscribe to a computed value derived from the store. The compute
    function receives the store and should return the value; the widget
    is marked dirty whenever that value changes. See L<Selkie::Store>. )
method subscribe-computed(Str:D $id, &compute) {
    $!store.subscribe-computed($id, &compute, self) if $!store;
}

has SetHash $!subscribed-ids = SetHash.new;

#|( Idempotent version of C<subscribe>. Tracks per-id registration so
    repeated C<set-store> calls (e.g. when the widget is reparented)
    don't create duplicate subscriptions. Prefer this over C<subscribe>
    when registering from C<on-store-attached>. )
method once-subscribe(Str:D $id, *@path) {
    return if $!subscribed-ids{$id};
    $!subscribed-ids{$id} = True;
    self.subscribe($id, |@path);
}

#| Idempotent version of C<subscribe-computed>. See C<once-subscribe>.
method once-subscribe-computed(Str:D $id, &compute) {
    return if $!subscribed-ids{$id};
    $!subscribed-ids{$id} = True;
    self.subscribe-computed($id, &compute);
}

#|( Update the widget's sizing declaration at runtime and request a
    re-layout. Use this when a widget's desired size changes — for
    example, a MultiLineInput growing as the user types more lines. )
method update-sizing(Sizing $s) {
    $!sizing = $s;
    self.mark-dirty;
    $!parent.mark-dirty if $!parent.defined;
}

# --- Framework-internal methods (public for cross-widget access) ---

#|( Create and take ownership of a notcurses plane, sized and positioned
    as specified. Called by parent layouts when they mount this widget.
    Override-safe: layout containers call this, leaf widgets never do. )
method init-plane(NcplaneHandle $parent-plane, UInt :$y = 0, UInt :$x = 0,
                  UInt :$rows = 1, UInt :$cols = 1) {
    my $opts = NcplaneOptions.new(:$y, :$x, :$rows, :$cols);
    $!plane = ncplane_create($parent-plane, $opts);
    die "Failed to create plane" without $!plane;
    $!rows = $rows;
    $!cols = $cols;
    $!y = $y;
    $!x = $x;
    # Paint the theme background onto this plane's base cell so
    # erase / unwritten regions carry the theme colour rather than
    # falling through to "terminal default" (which visibly breaks
    # themed backgrounds).
    self!sync-plane-base;
}

#|( Borrow an existing plane (owned elsewhere) as this widget's plane.
    Used by C<Selkie::App> to adopt the notcurses stdplane as the root
    screen's plane. This widget will not destroy the plane on cleanup.
    Rarely used outside the framework itself. )
method adopt-plane(NcplaneHandle $plane, UInt :$rows, UInt :$cols) {
    $!plane = $plane;
    $!owns-plane = False;
    $!rows = $rows;
    $!cols = $cols;
    $!y = 0;
    $!x = 0;
}

#|( Mark this widget dirty so it re-renders on the next frame. Also
    propagates dirty upwards to the parent chain so the render walk
    reaches it. Cheap — short-circuits if already dirty. Call this
    whenever your widget's visual state changes. )
method mark-dirty() {
    return if $!dirty;
    $!dirty = True;
    $!parent.mark-dirty if $!parent.defined;
}

#|( Recursively mark this widget and every descendant dirty. Use
    when a state change has layout implications that the default
    up-propagating C<mark-dirty> can't fully express — for example,
    a widget resizing itself causes every sibling's allocation to
    shift, and you want every descendant (not just the ancestors)
    to re-render fresh on the next frame.

    Pairs with L<mark-screen-dirty> for the common "start from the
    root of the attached tree" case. )
method mark-dirty-tree() {
    self.mark-dirty;
    # Use duck-typing instead of a type-check against Selkie::Container
    # — Container `does Selkie::Widget`, so a `use` here would be a
    # circular dependency. `can('children')` is the same condition
    # Selkie::App uses internally for its mark-all-dirty helper.
    if self.can('children') {
        for self.children -> $child {
            $child.mark-dirty-tree;
        }
    }
    if self.can('content') {
        my $c = self.content;
        $c.mark-dirty-tree if $c.defined;
    }
}

#|( Walk up to the root of the attached tree and flag the whole
    screen for a full render pass (via C<mark-dirty-tree>). Use
    when a local state change should invalidate every widget's
    layout — typically a dynamically-sized widget whose height or
    width just changed in a way that shifts its siblings'
    allocations.

    Cheap for rare events (rare meaning: not per-keystroke). For
    high-frequency triggers, prefer the default C<mark-dirty>
    propagation and let each render walk figure out what actually
    needs redrawing. )
method mark-screen-dirty() {
    my $root = self;
    while $root.parent.defined {
        $root = $root.parent;
    }
    $root.mark-dirty-tree;
}

#|( Clear the dirty flag. Call this as the last line of your C<render>
    method so the widget is skipped on subsequent frames until something
    changes. )
method clear-dirty() {
    $!dirty = False;
}

#|( Apply a C<Selkie::Style> (fg, bg, bold/italic/underline) to the
    widget's plane so subsequent C<ncplane_putstr_yx> calls pick up
    those attributes. Handles the three distinct notcurses calls
    (styles, fg, bg) in one shot. )
method apply-style(Selkie::Style $style) {
    ncplane_set_styles($!plane, $style.styles);
    ncplane_set_fg_rgb($!plane, $style.fg) if $style.fg.defined;
    ncplane_set_bg_rgb($!plane, $style.bg) if $style.bg.defined;
}

# --- Public API ---

#|( Resize the widget's plane to new dimensions. No-ops if the size is
    unchanged. Called by parent layouts — you shouldn't call this
    directly from a leaf widget. )
method resize(UInt $rows, UInt $cols) {
    return if $rows == $!rows && $cols == $!cols;
    self!apply-resize($rows, $cols);
    self!on-resize;
    self.mark-dirty;
}

#|( The framework's explicit terminal-resize protocol. Called when the
    terminal is resized; cascades through containers so every widget
    learns its new dimensions before the next render. Short-circuits
    when dims are unchanged — safe to call redundantly.

    Default implementation just delegates to C<resize()>; that's enough
    for leaf widgets. Containers override to cascade to their own
    children/content.

    Prefer this over C<resize()> when propagating a resize event from
    outside the layout pass. The built-in containers call
    C<handle-resize> on children from their C<layout-children> pass
    so the C<on-resize> hook fires for any widget whose dims actually
    changed.

    B<Custom containers> should override to cascade to their own
    children/content. If you hold child widgets in something other
    than C<self.children> (e.g. C<CardList>'s item hashes, C<Border>'s
    C<content>), your override is the only way the cascade reaches
    them. )
method handle-resize(UInt $rows, UInt $cols) {
    self.resize($rows, $cols);
}

#|( Optional hook called from C<handle-resize> when dimensions actually
    changed. Use for widget-specific bookkeeping that must update at
    the moment of resize rather than on the next render — recomputing
    cached wrap tables, invalidating pre-rendered buffers, resetting
    scroll offsets that no longer make sense, etc.

    Default is a no-op. Called after the plane has been resized and
    C<mark-dirty> has fired. )
method !on-resize() { }

#|( Move the widget's plane to new coordinates (relative to the parent
    plane). No-ops if the position is unchanged. Called by parent
    layouts. )
method reposition(UInt $y, UInt $x) {
    return if $y == $!y && $x == $!x;
    ncplane_move_yx($!plane, $y, $x) if $!plane;
    $!y = $y;
    $!x = $x;
}

#|( Render this widget to its plane. B<Required override>: the composing
    class must provide a body. Always guard with C<return without self.plane>,
    and call C<self.clear-dirty> at the end. )
method render() { ... }

#|( Park the widget off-screen — used by container swap operations
    (e.g. C<Border.set-content(:!destroy)>) when an outgoing widget
    needs to keep its state but stop appearing on the terminal.

    Default implementation repositions the widget's plane to a
    far-off Y so notcurses clips it. B<Override in widgets that own
    other notcurses resources whose visibility doesn't follow plane
    position> — most importantly Image, where the blit-plane carries
    a sprixel (Sixel/Kitty pixel image) that the terminal renders
    at an absolute on-screen position and won't clear just because
    the parent moved. Such widgets need to destroy their auxiliary
    plane(s) here so the sprixel gets removed from the terminal.

    Containers should override to recurse: park self + each
    descendant. )
method park() {
    self.reposition(10_000, 0) if $!plane;
}

#|( Register a keybind for this widget. Fires when the widget has
    focus and an unconsumed event matches the spec. See L<Selkie::Event>
    for the spec syntax (C<'a'>, C<'ctrl+q'>, C<'shift+tab'>, etc).

    Pass C<:description> to surface the bind in
    L<Selkie::Widget::HelpOverlay>. Binds without a description still
    work — they just don't appear in the help listing.

    Example:

        $list.on-key: 'd',      -> $ { delete-item }, :description('Delete');
        $list.on-key: 'ctrl+r', -> $ { refresh },     :description('Refresh');
    )
method on-key(Str:D $spec, &handler, Str :$description = '') {
    @!keybinds.push: Keybind.parse($spec, &handler, :$description);
}

#| Read-only access to this widget's registered keybinds. Used by
#| HelpOverlay to render a listing for the focused widget chain.
method keybinds(--> List) { @!keybinds.List }

method !check-keybinds(Selkie::Event $ev --> Bool) {
    for @!keybinds -> $kb {
        if $kb.matches($ev) {
            $kb.handler.($ev);
            return True;
        }
    }
    False;
}

#|( Handle a keyboard or mouse event. Return True if the event was
    consumed (the event will stop bubbling to the parent); False to let
    it continue up the chain. The default implementation dispatches to
    any registered keybinds — override to implement cursor movement,
    character input, click handling, etc. )
method handle-event(Selkie::Event $ev --> Bool) {
    self!check-keybinds($ev);
}

#|( Release any resources held by this widget. The default implementation
    destroys the plane. Override if your widget owns extra notcurses
    handles (e.g. ncvisual, child planes) or other resources — and
    always call C<self.destroy-plane> (or C<self!destroy-plane> if
    you're inside the same role/class) as the last step. )
method destroy() {
    self!destroy-plane;
}

method DESTROY() {
    self.destroy;
}
