NAME
====

Selkie::Widget - Base role composed by every Selkie widget

SYNOPSIS
========

A minimal custom widget that renders a fixed string:

```raku
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
```

Add it to any layout and it just works:

```raku
use Selkie::Sizing;

$vbox.add: My::Hello.new(sizing => Sizing.fixed(1));
```

DESCRIPTION
===========

`Selkie::Widget` is the role at the bottom of every widget in the framework. Compose it to create your own widget; Selkie handles the tree integration, rendering cycle, focus routing, theme inheritance, store plumbing, and memory management.

You almost never construct a `Selkie::Widget` directly — it's a role, so you `does Selkie::Widget` on your own class. The framework itself composes it to build every built-in widget (`Text`, `Button`, `ListView`, and so on).

What you get for free
---------------------

  * A notcurses plane to render into, created and destroyed for you

  * Theme inheritance from the widget tree

  * Themed plane-base painting so erase / unwritten cells show the theme background rather than the terminal default — applied on `init-plane`, `set-theme`, and every `apply-style` call

  * Keybind registration and event bubbling

  * Dirty tracking so your `render` method only runs when needed

  * Per-widget subscription to the reactive store

  * Clean shutdown when the widget goes out of scope

What you must provide
---------------------

At minimum, a `render` method. That's it.

What you may provide
--------------------

  * `handle-event` — to react to keyboard or mouse input when focused

  * `on-store-attached` — to wire up subscriptions when the store appears

  * `destroy` — to clean up anything beyond the plane (e.g. extra notcurses handles, file descriptors, subscriptions)

LIFECYCLE
=========

Construction happens in normal Raku fashion: `My::Widget.new(...)`. At this point the widget has no plane and no size. It's safe to store configuration on the object but not to call notcurses functions.

When the widget is added to a parent layout (via `$parent.add($child)`), the parent calls `init-plane` to create a notcurses plane sized to its share of the layout. After this point `self.plane` returns a valid handle, and `self.rows` / `self.cols` reflect the plane's dimensions.

Each frame, the framework walks the tree and calls `render` on any widget whose `is-dirty` is true. Your render method should:

  * Erase the plane with `ncplane_erase(self.plane)`

  * Apply styles with `self.apply-style($style)`

  * Write to the plane with notcurses calls

  * Call `self.clear-dirty` at the end

When the widget is removed or the program exits, `destroy` is called and the plane is freed.

OVERRIDE POINTS
===============

The public API is organised into three buckets.

Required override
-----------------

  * `render` — draw yourself onto `self.plane`. Must be defined by the composing class.

Optional overrides
------------------

  * `handle-event($ev --` Bool)> — return True if you consumed the event

  * `destroy` — call `self.destroy-plane` and clean up any extras

  * `on-store-attached($store)` — implement this (no inherited default) to register subscriptions

Do not override
---------------

  * `init-plane`, `adopt-plane` — called by layout containers

  * `mark-dirty`, `clear-dirty` — called by the render cycle

  * `set-viewport` — called by parent layouts

EXAMPLES
========

Example 1 — A static colored bar
--------------------------------

The simplest useful widget. A solid block of color spanning its full size. Good for spacers or visual dividers.

```raku
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
```

Use it like:

```raku
$vbox.add: My::ColorBar.new(color => 0xFF5555, sizing => Sizing.fixed(1));
```

Example 2 — A focusable toggle that emits on change
---------------------------------------------------

A box that flips a boolean when the user presses Space or Enter. The state is owned by the widget; interested app code subscribes by tapping the `on-toggle` Supply. This is the canonical leaf-widget pattern in Selkie — widgets emit, app code dispatches to the store.

```raku
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
```

Consuming app code:

```raku
my $toggle = My::Toggle.new(sizing => Sizing.fixed(1));
$vbox.add($toggle);
$toggle.on-toggle.tap: -> Bool $on {
    # Tap fires whenever state flips. Dispatch to the store from here.
    $app.store.dispatch('setting/changed', value => $on);
};
```

Example 3 — Registering a custom keybind
----------------------------------------

Widgets can register per-instance keybinds with `on-key`. These fire when the widget is focused (or, if unfocused, are available for the parent chain to delegate to). Useful for shortcuts scoped to a specific view.

```raku
my $list-view = Selkie::Widget::ListView.new(sizing => Sizing.flex);

# 'a' on the list triggers "add"
$list-view.on-key: 'a', -> $ {
    open-add-dialog();
};

# 'd' with the list focused deletes the cursor item
$list-view.on-key: 'd', -> $ {
    delete-current-item();
};
```

Keybinds with a modifier (`ctrl+`, `alt+`, `super+`) work even when a text input is focused — the input lets modified keys bubble up. Bare character keybinds get consumed by text inputs, so reserve them for list-style widgets.

Example 4 — A widget that reacts to store state
-----------------------------------------------

When a widget's appearance depends on shared application state, subscribe to the store from `on-store-attached`. The framework calls this once per `set-store` call, so use `once-subscribe` / `once-subscribe-computed` to avoid duplicate registrations across repeated calls.

```raku
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
```

SEE ALSO
========

  * [Selkie::Container](Selkie--Container.md) — for widgets that hold children

  * [Selkie::Sizing](Selkie--Sizing.md) — the fixed/percent/flex sizing model

  * [Selkie::Theme](Selkie--Theme.md) and [Selkie::Style](Selkie--Style.md) — styling inherited through the tree

  * [Selkie::Event](Selkie--Event.md) — the keyboard/mouse event abstraction

  * [Selkie::Store](Selkie--Store.md) — the reactive state store

### has Int $.widget-id

A monotonically-increasing integer identifier unique to each widget instance. Assigned at construction and never changes. Useful as a key when you need identity-stable references in subscriptions or debug output.

### has Selkie::Widget $.parent

The containing widget, set by the parent layout when this widget is added to it. Read-only in practice — layouts manage this — but exposed as `is rw` so internal helpers can reparent.

### has Selkie::Sizing::Sizing $.sizing

How this widget wants to be sized by its parent layout. See [Selkie::Sizing](Selkie--Sizing.md): `Sizing.fixed($n)`, `Sizing.percent($n)`, or `Sizing.flex($n = 1)`. Defaults to `Sizing.flex`.

### has Bool $.focusable

Whether this widget can receive focus via Tab / Shift-Tab cycling or direct `$app.focus($widget)` calls. Leaf input widgets typically override this to True in their `new` method: method new(*%args) { %args<focusable> //= True; callwith(|%args); }

### method plane

```raku
method plane() returns Notcurses::Native::Types::NcplaneHandle
```

Returns the notcurses plane this widget renders to, or the type object `NcplaneHandle` if the widget has not been added to a parent yet. Always guard with `return without self.plane;` at the top of `render`.

### method rows

```raku
method rows() returns UInt
```

Current row height of the widget's plane.

### method cols

```raku
method cols() returns UInt
```

Current column width of the widget's plane.

### method y

```raku
method y() returns UInt
```

Y offset relative to the parent plane.

### method x

```raku
method x() returns UInt
```

X offset relative to the parent plane.

### method is-dirty

```raku
method is-dirty() returns Bool
```

True if this widget needs to be re-rendered on the next frame.

### method abs-y

```raku
method abs-y() returns Int
```

Absolute Y position on the screen — the parent layout computes this by accumulating its own `abs-y` with this widget's local offset. Useful for overlay positioning.

### method abs-x

```raku
method abs-x() returns Int
```

Absolute X position on the screen. See `abs-y`.

### method viewport-rows

```raku
method viewport-rows() returns UInt
```

Number of rows actually visible on screen — may be smaller than `rows` if a parent ScrollView is clipping us.

### method viewport-cols

```raku
method viewport-cols() returns UInt
```

Number of columns actually visible on screen. See `viewport-rows`.

### method set-viewport

```raku
method set-viewport(
    Int :$abs-y!,
    Int :$abs-x!,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Mu
```

Called by parent layouts during layout. Propagates absolute screen position and visible bounds to this widget. You don't call this yourself unless you're implementing a layout container.

### method theme

```raku
method theme() returns Selkie::Theme
```

The effective theme for this widget. Walks up the parent chain until it finds a widget with an explicit theme, falling back to `Selkie::Theme.default`. Use this in `render` rather than caching a theme reference, so theme changes propagate correctly.

### method set-theme

```raku
method set-theme(
    Selkie::Theme $t
) returns Mu
```

Override the theme for this widget and its subtree. The new theme is used on the next render. Useful for scoping a different look to a specific panel (e.g. a modal with its own palette).

### method sync-plane-base

```raku
method sync-plane-base() returns Mu
```

Paint this widget's plane base cell using the active theme's `base` style so `ncplane_erase` and any cell the widget doesn't explicitly write will carry the theme's background / foreground rather than notcurses's default-empty state (which renders as the terminal's own default). Safe to call repeatedly and before the plane or theme are ready — no-op in those cases.

### method store

```raku
method store() returns Mu
```

The [Selkie::Store](Selkie--Store.md) attached to this widget, or `Nil` if no store has been set yet. Propagates automatically from parent to child.

### method set-store

```raku
method set-store(
    $store
) returns Mu
```

Attach a store to this widget. Called automatically by parent containers when a widget is added to the tree and a store exists. Recursively propagates to children and Border/Modal content. Fires `on-store-attached` on the widget if implemented. You shouldn't need to call this directly — just add the widget to a tree that has a store.

### method dispatch

```raku
method dispatch(
    Str:D $event,
    *%payload
) returns Mu
```

Convenience for dispatching a store event. Equivalent to `self.store.dispatch($event, |%payload)` but gracefully no-ops if no store is attached. Most widgets shouldn't dispatch directly — prefer emitting on a Supply and letting app code dispatch.

### method subscribe

```raku
method subscribe(
    Str:D $id,
    *@path
) returns Mu
```

Subscribe this widget to a path in the store. When the value at that path changes, the widget is marked dirty and re-renders. See [Selkie::Store](Selkie--Store.md) for details. Typically called from `on-store-attached`.

### method subscribe-computed

```raku
method subscribe-computed(
    Str:D $id,
    &compute
) returns Mu
```

Subscribe to a computed value derived from the store. The compute function receives the store and should return the value; the widget is marked dirty whenever that value changes. See [Selkie::Store](Selkie--Store.md).

### method once-subscribe

```raku
method once-subscribe(
    Str:D $id,
    *@path
) returns Mu
```

Idempotent version of `subscribe`. Tracks per-id registration so repeated `set-store` calls (e.g. when the widget is reparented) don't create duplicate subscriptions. Prefer this over `subscribe` when registering from `on-store-attached`.

### method once-subscribe-computed

```raku
method once-subscribe-computed(
    Str:D $id,
    &compute
) returns Mu
```

Idempotent version of `subscribe-computed`. See `once-subscribe`.

### method update-sizing

```raku
method update-sizing(
    Selkie::Sizing::Sizing $s
) returns Mu
```

Update the widget's sizing declaration at runtime and request a re-layout. Use this when a widget's desired size changes — for example, a MultiLineInput growing as the user types more lines.

### method init-plane

```raku
method init-plane(
    Notcurses::Native::Types::NcplaneHandle $parent-plane,
    Int :$y where { ... } = 0,
    Int :$x where { ... } = 0,
    Int :$rows where { ... } = 1,
    Int :$cols where { ... } = 1
) returns Mu
```

Create and take ownership of a notcurses plane, sized and positioned as specified. Called by parent layouts when they mount this widget. Override-safe: layout containers call this, leaf widgets never do.

### method adopt-plane

```raku
method adopt-plane(
    Notcurses::Native::Types::NcplaneHandle $plane,
    Int :$rows where { ... },
    Int :$cols where { ... }
) returns Mu
```

Borrow an existing plane (owned elsewhere) as this widget's plane. Used by `Selkie::App` to adopt the notcurses stdplane as the root screen's plane. This widget will not destroy the plane on cleanup. Rarely used outside the framework itself.

### method mark-dirty

```raku
method mark-dirty() returns Mu
```

Mark this widget dirty so it re-renders on the next frame. Also propagates dirty upwards to the parent chain so the render walk reaches it. Cheap — short-circuits if already dirty. Call this whenever your widget's visual state changes.

### method clear-dirty

```raku
method clear-dirty() returns Mu
```

Clear the dirty flag. Call this as the last line of your `render` method so the widget is skipped on subsequent frames until something changes.

### method apply-style

```raku
method apply-style(
    Selkie::Style $style
) returns Mu
```

Apply a `Selkie::Style` (fg, bg, bold/italic/underline) to the widget's plane so subsequent `ncplane_putstr_yx` calls pick up those attributes. Handles the three distinct notcurses calls (styles, fg, bg) in one shot.

### method resize

```raku
method resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Resize the widget's plane to new dimensions. No-ops if the size is unchanged. Called by parent layouts — you shouldn't call this directly from a leaf widget.

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

The framework's explicit terminal-resize protocol. Called when the terminal is resized; cascades through containers so every widget learns its new dimensions before the next render. Short-circuits when dims are unchanged — safe to call redundantly. Default implementation just delegates to `resize()`; that's enough for leaf widgets. Containers override to cascade to their own children/content. Prefer this over `resize()` when propagating a resize event from outside the layout pass. The built-in containers call `handle-resize` on children from their `layout-children` pass so the `on-resize` hook fires for any widget whose dims actually changed. **Custom containers** should override to cascade to their own children/content. If you hold child widgets in something other than `self.children` (e.g. `CardList`'s item hashes, `Border`'s `content`), your override is the only way the cascade reaches them.

### method on-resize

```raku
method on-resize() returns Mu
```

Optional hook called from `handle-resize` when dimensions actually changed. Use for widget-specific bookkeeping that must update at the moment of resize rather than on the next render — recomputing cached wrap tables, invalidating pre-rendered buffers, resetting scroll offsets that no longer make sense, etc. Default is a no-op. Called after the plane has been resized and `mark-dirty` has fired.

### method reposition

```raku
method reposition(
    Int $y where { ... },
    Int $x where { ... }
) returns Mu
```

Move the widget's plane to new coordinates (relative to the parent plane). No-ops if the position is unchanged. Called by parent layouts.

### method render

```raku
method render() returns Mu
```

Render this widget to its plane. **Required override**: the composing class must provide a body. Always guard with `return without self.plane`, and call `self.clear-dirty` at the end.

### method park

```raku
method park() returns Mu
```

Park the widget off-screen — used by container swap operations (e.g. `Border.set-content(:!destroy)`) when an outgoing widget needs to keep its state but stop appearing on the terminal. Default implementation repositions the widget's plane to a far-off Y so notcurses clips it. **Override in widgets that own other notcurses resources whose visibility doesn't follow plane position** — most importantly Image, where the blit-plane carries a sprixel (Sixel/Kitty pixel image) that the terminal renders at an absolute on-screen position and won't clear just because the parent moved. Such widgets need to destroy their auxiliary plane(s) here so the sprixel gets removed from the terminal. Containers should override to recurse: park self + each descendant.

### method on-key

```raku
method on-key(
    Str:D $spec,
    &handler,
    Str :$description = ""
) returns Mu
```

Register a keybind for this widget. Fires when the widget has focus and an unconsumed event matches the spec. See [Selkie::Event](Selkie--Event.md) for the spec syntax (`'a'`, `'ctrl+q'`, `'shift+tab'`, etc). Pass `:description` to surface the bind in [Selkie::Widget::HelpOverlay](Selkie--Widget--HelpOverlay.md). Binds without a description still work — they just don't appear in the help listing. Example: $list.on-key: 'd', -> $ { delete-item }, :description('Delete'); $list.on-key: 'ctrl+r', -> $ { refresh }, :description('Refresh');

### method keybinds

```raku
method keybinds() returns List
```

Read-only access to this widget's registered keybinds. Used by HelpOverlay to render a listing for the focused widget chain.

### method handle-event

```raku
method handle-event(
    Selkie::Event $ev
) returns Bool
```

Handle a keyboard or mouse event. Return True if the event was consumed (the event will stop bubbling to the parent); False to let it continue up the chain. The default implementation dispatches to any registered keybinds — override to implement cursor movement, character input, click handling, etc.

### method destroy

```raku
method destroy() returns Mu
```

Release any resources held by this widget. The default implementation destroys the plane. Override if your widget owns extra notcurses handles (e.g. ncvisual, child planes) or other resources — and always call `self.destroy-plane` (or `self!destroy-plane` if you're inside the same role/class) as the last step.

