[![Actions Status](https://github.com/m-doughty/Selkie/actions/workflows/test.yml/badge.svg)](https://github.com/m-doughty/Selkie/actions)

NAME
====

Selkie - High-level TUI framework built on Notcurses

SYNOPSIS
========

```raku
use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Widget::TextStream;
use Selkie::Widget::TextInput;
use Selkie::Sizing;

my $app = Selkie::App.new;
my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

my $log = Selkie::Widget::TextStream.new(sizing => Sizing.flex);
$root.add($log);

my $input = Selkie::Widget::TextInput.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Type here...',
);
$root.add($input);
$app.focus($input);

$input.on-submit.tap: -> $text {
    $log.append($text);
    $input.clear;
};

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;
```

DESCRIPTION
===========

Selkie is a retained-mode TUI framework for Raku, built on [Notcurses::Native](https://github.com/m-doughty/Notcurses-Native). It provides a hierarchical widget tree with automatic memory management, declarative layout sizing, virtual scrolling, theming, and a re-frame-style reactive store for application state.

Selkie is designed for building full-screen interactive terminal applications: chat clients, dashboards, editors, browsers, configuration UIs. It handles the low-level notcurses rendering, focus cycling, event routing, and terminal resize behaviour so you can focus on your application.

Design goals
------------

  * **Retained mode** — build a widget tree once, mutate it as state changes. Re-renders only dirty widgets.

  * **Declarative sizing** — fixed, percentage, or flex units on each widget. Layouts allocate space automatically.

  * **Safe by default** — all notcurses handles are owned by widgets and freed on destroy. No manual memory management.

  * **Reactive state** — optional centralized store with event dispatch, handlers returning effects, and path/computed subscriptions.

  * **Composable** — every widget is a role-composed class. Build your own by composing `Selkie::Widget` or `Selkie::Container`.

INSTALLATION
============

```bash
zef install Selkie
```

EXAMPLES
========

The `examples/` directory has six runnable apps that together demonstrate every widget and store pattern in the framework. Each is self-contained and heavily commented — read them in this order:

  * `counter.raku` — The smallest correct-pattern app. VBox, Text, Button, store handler returning `(db =` ...)>, path subscription, global keybind. Start here.

  * `settings.raku` — A form covering every input widget: TextInput, MultiLineInput, Checkbox, RadioGroup, Select, Button. Plus ConfirmModal, plain Modal, computed subscription for live form summary, and silent setters that sync inputs from store state without feedback loops.

  * `file-viewer.raku` — Split layout with a FileBrowser modal, Image preview, ScrollView for long text. Demonstrates a callback subscription that toggles which preview widget is visible based on the selected file's kind.

  * `tasks.raku` — Todo list with ListView, TextInput, Checkbox filter, ConfirmModal for deletion, Toast notifications, and ScreenManager (list ↔ stats screen).

  * `job-runner.raku` — ProgressBar (both determinate and indeterminate), TextStream log, async store effect for background work, dispatch-effect chaining, frame callback driving animation.

  * `chat.raku` — CardList of variable-height RichText cards, MultiLineInput compose, Border auto-focus highlight, Toast, runtime theme toggle (Ctrl+T).

Run any of them with:

```bash
cd Selkie
raku -I lib examples/counter.raku
```

After `zef install .` in the Selkie directory, the `-I lib` flag is no longer required.

CORE CONCEPTS
=============

Widgets
-------

Everything on screen is a `Selkie::Widget`. A widget owns a notcurses plane (a rectangular rendering surface), tracks its size and position, and knows how to render itself. Widgets are usually composed from the `Selkie::Widget` role — which provides the lifecycle, keybinds, store integration, and viewport machinery — and add their own rendering logic.

Every widget has:

  * `plane` — the notcurses handle it renders to (managed for you)

  * `rows`, `cols` — current dimensions

  * `sizing` — a `Selkie::Sizing` declaring how space should be allocated

  * `focusable` — whether Tab/Shift-Tab can move focus to it

  * `parent` — the containing widget

  * `theme` — inherited from the parent chain, or set explicitly

Containers
----------

Containers hold other widgets. The `Selkie::Container` role adds `add(widget)`, `remove(widget)`, `clear()`, and `children()`. Containers are responsible for positioning and sizing their children.

Layouts (VBox, HBox, Split) are the standard containers. You can compose `Selkie::Container` to build your own.

Sizing
------

Each widget declares how it wants to be sized by its parent layout:

```raku
use Selkie::Sizing;

Sizing.fixed(10)    # exactly 10 rows/cols
Sizing.percent(50)  # 50% of parent
Sizing.flex         # flex factor 1 (default)
Sizing.flex(2)      # flex factor 2 (gets twice as much leftover space)
```

Layouts allocate fixed and percent children first, then distribute the remainder proportionally to flex children.

The widget tree
---------------

A Selkie app is a tree of widgets rooted at a screen. The tree is built explicitly: you instantiate widgets and add them to layouts. The framework walks the tree to dispatch events, propagate themes and the store, and render dirty subtrees.

Dirty tracking
--------------

Widgets mark themselves dirty when their state changes (`self.mark-dirty`). Dirty propagates up to the root. Each frame, the app walks the tree and re-renders dirty widgets. Calling `mark-dirty` on a widget that's already dirty short-circuits, so cascading updates are cheap.

APP LIFECYCLE
=============

`Selkie::App` is the entry point. It initializes notcurses, runs the event loop, and manages screens, modals, toasts, and focus.

```raku
use Selkie::App;

my $app = Selkie::App.new;

$app.add-screen('main', $root-container);
$app.switch-screen('main');
$app.focus($first-focusable-widget);

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.on-frame(-> { ... });   # called each frame (~60fps)

$app.run;   # blocks until quit
```

Screens
-------

Apps often have multiple top-level views — a login screen plus a main screen, for example. Register each as a named screen:

```raku
$app.add-screen('login', $login-root);
$app.add-screen('main',  $main-root);
$app.switch-screen('login');    # shows login, hides main
```

Only the active screen renders and receives events. Inactive screens are parked off-screen but keep their state.

Modals
------

Open a modal dialog over the current screen:

```raku
my $modal = Selkie::Widget::Modal.new(width-ratio => 0.5, height-ratio => 0.3);
$modal.set-content($some-widget);
$app.show-modal($modal);
$app.focus($some-focusable-inside-modal);

$modal.on-close.tap: -> $ {
    $app.close-modal;
};
```

While a modal is active, events are routed to the modal's focused descendant first; only Tab, Shift-Tab, and Esc bubble to the app. Esc closes the modal by default.

Toasts
------

Transient messages that auto-dismiss:

```raku
$app.toast('Saved!', 2);  # message, seconds
```

Frame callbacks
---------------

Run code every frame. Essential for streaming updates (which aren't tied to user input):

```raku
$app.on-frame: {
    $my-progress.tick;      # animate indeterminate progress bar
    $my-stream-widget.pull; # pull latest tokens from a stream
};
```

EVENTS AND KEYBINDS
===================

`Selkie::Event` wraps keyboard, mouse, and resize events from notcurses. Widgets implement `handle-event(Selkie::Event $ev --` Bool)>, returning `True` if the event was consumed. Unconsumed events bubble to the parent, then to the app's global keybinds.

Per-widget keybinds
-------------------

```raku
$list.on-key: 'a', -> $ { self!add-item };
$list.on-key: 'd', -> $ { self!delete-item };
```

Bare character keybinds on a focusable widget fire when it's focused.

Global keybinds
---------------

```raku
$app.on-key('ctrl+q', -> $ { $app.quit });
$app.on-key('alt+1',  -> $ { $app.focus($pane1) });
```

Global keybinds must include a modifier (Ctrl, Alt, Super) to avoid clashing with text input.

Event spec syntax
-----------------

Keybind specs are strings:

  * `'a'`, `'Q'`, `'?'` — single character

  * `'tab'`, `'enter'`, `'esc'`, `'space'`, `'backspace'` — named keys

  * `'f1'` through `'f60'` — function keys

  * `'up'`, `'down'`, `'left'`, `'right'`, `'home'`, `'end'`, `'pgup'`, `'pgdown'` — navigation

  * `'ctrl+X'`, `'alt+X'`, `'shift+X'`, `'super+X'` — modifiers (combinable)

Letter keybinds are case-insensitive. The framework handles Shift correctly (e.g. `'!'` fires for `shift+1`).

Focus cycling
-------------

`Tab` and `Shift-Tab` cycle focus through focusable widgets on the active screen (or modal). `Selkie::App` handles this automatically. You can also drive it programmatically:

```raku
$app.focus-next;
$app.focus-prev;
$app.focus($specific-widget);
```

LAYOUTS
=======

Selkie::Layout::VBox
--------------------

Arranges children top to bottom.

```raku
my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$vbox.add: Selkie::Widget::Text.new(text => 'Header', sizing => Sizing.fixed(1));
$vbox.add: $main-content-widget;   # sizing => Sizing.flex (fills remainder)
$vbox.add: Selkie::Widget::Text.new(text => 'Footer', sizing => Sizing.fixed(1));
```

Selkie::Layout::HBox
--------------------

Arranges children left to right. Same API as VBox.

Selkie::Layout::Split
---------------------

Two-pane split with a draggable-looking divider (not interactive yet — ratio is programmatic).

```raku
my $split = Selkie::Layout::Split.new(
    orientation => 'horizontal',  # left | right panes
    ratio       => 0.3,            # 30% | 70%
    sizing      => Sizing.flex,
);
$split.set-first($sidebar);
$split.set-second($main-content);
```

Set `orientation =` 'vertical'> for top/bottom panes.

WIDGETS
=======

Selkie::Widget::Text
--------------------

Static styled text with word wrapping.

```raku
my $text = Selkie::Widget::Text.new(
    text   => 'Hello, world',
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    sizing => Sizing.fixed(1),
);
$text.set-text('Updated');
```

Selkie::Widget::RichText
------------------------

Styled text made of multiple spans, each with its own style. Handles word-wrap across span boundaries.

```raku
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;

my $rich = Selkie::Widget::RichText.new;
$rich.set-content([
    Span.new(text => 'Error: ',
        style => Selkie::Style.new(fg => 0xFF5555, bold => True)),
    Span.new(text => 'file not found'),
]);
```

Selkie::Widget::TextStream
--------------------------

Append-only log with ring buffer and auto-scroll. Ideal for streaming LLM output, chat logs, command output.

```raku
my $stream = Selkie::Widget::TextStream.new(
    max-lines => 10000,
    sizing    => Sizing.flex,
);
$stream.append('New line');
$stream.start-supply($some-supply);  # auto-append from a Supply
```

Auto-follows (scrolls to bottom on append) unless the user has scrolled up manually.

Selkie::Widget::TextInput
-------------------------

Single-line text input with cursor, horizontal scroll, and optional mask for passwords.

```raku
my $input = Selkie::Widget::TextInput.new(
    placeholder => 'Search...',
    sizing      => Sizing.fixed(1),
);

$input.on-submit.tap: -> $text { ... };
$input.on-change.tap: -> $text { ... };

# Password field
my $pw = Selkie::Widget::TextInput.new(mask-char => '•');
```

Selkie::Widget::MultiLineInput
------------------------------

Multi-line text input with word wrapping, 2D cursor, and a configurable max visible height.

```raku
my $area = Selkie::Widget::MultiLineInput.new(
    placeholder => 'Type a message... (Ctrl+Enter to send)',
    max-lines   => 6,
    sizing      => Sizing.fixed(1),  # grows as typed, up to max-lines
);

$area.on-submit.tap: -> $text { ... };  # Ctrl+Enter
# Plain Enter inserts a newline (good for pasted content).
```

Selkie::Widget::Button
----------------------

Focusable clickable button. Emits on Enter or Space.

```raku
my $btn = Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.fixed(1));
$btn.on-press.tap: -> $ { do-something };
```

Selkie::Widget::Checkbox
------------------------

Focusable boolean toggle. Space or Enter toggles. Renders as `[x] label` or `[ ] label`.

```raku
my $cb = Selkie::Widget::Checkbox.new(
    label => 'Enable notifications',
    sizing => Sizing.fixed(1),
);
$cb.on-change.tap: -> Bool $checked { ... };
$cb.set-checked(True);
```

Selkie::Widget::RadioGroup
--------------------------

Focusable single-selection list with `(●)`/`( )` indicators. Up/Down moves the cursor, Enter/Space commits the selection. Cursor and selection are independent — the user can navigate without changing selection.

```raku
my $radio = Selkie::Widget::RadioGroup.new(sizing => Sizing.fixed(3));
$radio.set-items(<Small Medium Large>);
$radio.on-change.tap: -> UInt $idx {
    say "Selected: {$radio.selected-label}";
};
```

Selkie::Widget::Select
----------------------

Compact dropdown picker. Closed state shows the current value with a `▼` marker. Enter/Space opens the dropdown as a child plane rendered on top of surrounding widgets. Esc cancels, Enter/Space commits.

```raku
my $select = Selkie::Widget::Select.new(
    placeholder => 'Choose a model...',
    max-visible => 8,      # max items shown in the open dropdown
    sizing      => Sizing.fixed(1),
);
$select.set-items(<gpt-4 claude-opus local-model>);
$select.on-change.tap: -> UInt $idx {
    say $select.selected-value;
};
```

Selkie::Widget::ProgressBar
---------------------------

Non-focusable progress indicator. Supports determinate (0.0..1.0 with percentage) and indeterminate (bouncing animation driven by `tick()`) modes.

```raku
# Determinate
my $pb = Selkie::Widget::ProgressBar.new(sizing => Sizing.fixed(1));
$pb.set-value(0.42);   # 42%

# Indeterminate (animate via frame callback)
my $loading = Selkie::Widget::ProgressBar.new(
    indeterminate    => True,
    show-percentage  => False,
    frames-per-step  => 4,
    sizing           => Sizing.fixed(1),
);
$app.on-frame: { $loading.tick };
```

Selkie::Widget::ListView
------------------------

Scrollable single-select list of strings with keyboard navigation and scrollbar.

```raku
my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
$list.set-items(<Alpha Beta Gamma Delta>);
$list.on-select.tap:   -> $name { ... };   # cursor moved
$list.on-activate.tap: -> $name { ... };   # Enter pressed
```

Selkie::Widget::CardList
------------------------

Scrollable list of variable-height widgets. Cursor navigates cards; the selected card is always fully visible, with clipping on the opposite end indicated to the card (for e.g. truncation ellipsis).

Use this when each item is richer than a string — e.g. chat messages, character cards, task cards.

```raku
my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);
$cards.add-item(
    widget => $some-card-widget,
    root   => $some-container-wrapping-it,
    height => 5,
    border => $optional-border-for-focus-highlight,
);
$cards.on-select.tap: -> UInt $idx { ... };
```

Selkie::Widget::ScrollView
--------------------------

Generic virtual-scrolling container. Renders only visible children — children outside the viewport are moved off-screen, so very long lists stay cheap.

```raku
my $scroll = Selkie::Widget::ScrollView.new(sizing => Sizing.flex);
$scroll.add($_) for @many-widgets;
$scroll.scroll-to-end;
```

Children should implement `logical-height()` so the ScrollView can compute offsets. Widgets that care about partial rendering (Text, RichText, TextStream) implement `render-region(offset, height)` for partial-row clipping.

Selkie::Widget::Border
----------------------

Decorative frame around a child widget. Auto-highlights when its descendant has focus (via a store subscription on `ui.focused-widget`).

```raku
my $border = Selkie::Widget::Border.new(
    title  => 'Characters',
    sizing => Sizing.fixed(20),
);
$border.set-content($inner-widget);

$border.hide-top-border    = True;   # useful when stacking borders
$border.hide-bottom-border = True;
```

Requires at least 3x3. Redraws its edges after content to cover pixel bleed from child image blits.

Selkie::Widget::Modal
---------------------

Centered overlay dialog with dimmed background.

```raku
my $modal = Selkie::Widget::Modal.new(
    width-ratio    => 0.5,
    height-ratio   => 0.3,
    dim-background => True,
);
$modal.set-content($my-form);
$modal.on-close.tap: -> $ { $app.close-modal };
$app.show-modal($modal);
```

Modal closes on Esc by default. While open, all events are scoped to its content (focus trap) except Tab/Shift-Tab/Esc.

Selkie::Widget::ConfirmModal
----------------------------

Pre-built yes/no confirmation modal.

```raku
my $cm = Selkie::Widget::ConfirmModal.new;
$cm.build(
    title     => 'Delete file?',
    message   => "Really delete 'report.pdf'?",
    yes-label => 'Delete',
    no-label  => 'Cancel',
);
$cm.on-result.tap: -> Bool $confirmed {
    $app.close-modal;
    do-delete if $confirmed;
};
$app.show-modal($cm.modal);
$app.focus($cm.no-button);   # safe default
```

Selkie::Widget::FileBrowser
---------------------------

Modal file picker with shell-style path completion, extension filtering, and an optional dotfile toggle.

```raku
my $browser = Selkie::Widget::FileBrowser.new;
my $modal = $browser.build(
    extensions     => <png json>,
    show-dotfiles  => False,
    width-ratio    => 0.7,
    height-ratio   => 0.7,
);
$browser.on-select.tap: -> Str $path {
    $app.close-modal;
    load-file($path);
};
$app.show-modal($modal);
$app.focus($browser.focusable-widget);
```

Selkie::Widget::Toast
---------------------

Transient notification banner (usually managed via `$app.toast`, but accessible directly for custom styling).

Selkie::Widget::Image
---------------------

Displays an image file. Uses notcurses pixel blitter if the terminal supports it (Kitty, iTerm2, some others), falling back to block/unicode art otherwise.

```raku
my $img = Selkie::Widget::Image.new(
    file   => 'avatar.png',
    sizing => Sizing.fixed(20),
);
$img.set-file('new-avatar.png');
$img.clear-image;
```

Be aware: pixel-blitted images extend past parent plane bounds in notcurses. Wrap in a `Border` (which redraws its edges after content) or lay out with enough margin to avoid bleed.

THEMING
=======

`Selkie::Style` represents a text style (fg, bg, bold, italic, underline, strikethrough). `Selkie::Theme` is a collection of named style slots:

```raku
use Selkie::Style;
use Selkie::Theme;

my $theme = Selkie::Theme.new(
    base              => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x000000),
    text              => Selkie::Style.new(fg => 0xEEEEEE),
    text-dim          => Selkie::Style.new(fg => 0x888888),
    text-highlight    => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
    border            => Selkie::Style.new(fg => 0x444444),
    border-focused    => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    input             => Selkie::Style.new(fg => 0xEEEEEE, bg => 0x1A1A2E),
    input-focused     => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x2A2A3E),
    input-placeholder => Selkie::Style.new(fg => 0x606080, italic => True),
    scrollbar-track   => Selkie::Style.new(fg => 0x333333),
    scrollbar-thumb   => Selkie::Style.new(fg => 0x7AA2F7),
    divider           => Selkie::Style.new(fg => 0x444444),
);

my $app = Selkie::App.new(theme => $theme);
```

Widgets resolve theme via inheritance: if a widget has no explicit theme, it walks up the parent chain until one is found, defaulting to `Selkie::Theme.default` (a dark palette) at the root.

Set a theme on a subtree to scope overrides:

```raku
$widget.set-theme($special-theme);
```

For ad-hoc per-slot values, use `$theme.custom{...}` and `$theme.slot('my-slot')`.

REACTIVE STORE
==============

Selkie includes an optional re-frame-inspired store for centralized application state. Use it when you have shared state accessed by multiple widgets, or need derived values that update reactively.

Quick example
-------------

```raku
use Selkie::Store;

my $store = Selkie::Store.new;

# Register a handler for an event. Handler returns effects (not mutations).
$store.register-handler('counter/increment', -> $st, %ev {
    my $current = $st.get-in('counter') // 0;
    (db => { counter => $current + 1 },);
});

# Subscribe a widget to a path. It's marked dirty when the value changes.
$store.subscribe('my-counter', ['counter'], $widget);

# Dispatch an event from anywhere.
$store.dispatch('counter/increment');

# The app ticks the store each frame, processing the queue and firing subs.
```

State access
------------

`%!db` is a nested Hash. Use path-based access:

```raku
$store.get-in('app', 'user', 'name');  # deep read; returns Nil if missing
$store.assoc-in('app', 'user', 'name', value => 'Alice');  # deep write
```

Prefer dispatch-and-handle over direct `assoc-in` from app code — handlers keep state changes auditable and composable.

Handlers and effects
--------------------

Handlers are pure functions: `(store, payload) --` effects>. An effect is a `Pair` where the key is a registered effect name and the value is its parameters.

Built-in effects:

  * `db =` {...}> — deep-merge into the state tree

  * `dispatch =` { event => 'name', ...payload }> — enqueue another event

  * `async =` { work => &fn, on-success => 'name', on-failure => 'name' }> — run in a thread, dispatch a follow-up event with the result

```raku
$store.register-handler('user/load', -> $st, %ev {
    (async => {
        work        => -> { fetch-user-from-api(%ev<id>) },
        on-success  => 'user/loaded',
        on-failure  => 'user/load-failed',
    },);
});

$store.register-handler('user/loaded', -> $st, %ev {
    (db => { user => %ev<result> },);
});
```

You can return multiple effects from one handler by returning a list of Pairs, or a single Hash with multiple keys.

Subscriptions
-------------

Three kinds, all triggered at each frame tick when the watched value changes:

  * `subscribe($id, @path, $widget)` — watch a state path; marks widget dirty on change

  * `subscribe-computed($id, &compute, $widget)` — watch a derived value

  * `subscribe-with-callback($id, &compute, &callback, $widget)` — derive + invoke callback with new value

```raku
# Rebuild the list UI when items change
$store.subscribe-with-callback(
    'my-items',
    -> $s { $s.get-in('app', 'items') // [] },
    -> @items { $list-view.set-items(@items.map(*.name)) },
    $list-view,
);
```

**Important:** when writing compute closures, never use `return` inside them — `return` targets the enclosing routine, not the block. Use `if/else` to yield the final expression.

Store and widgets
-----------------

`Selkie::App` owns a default `Selkie::Store`. Widgets added to the tree automatically get a reference (propagation is one-way, parent to child). Widgets can call `self.dispatch(event, payload)` and `self.subscribe(...)` as convenience methods — but they usually shouldn't. The canonical pattern is: widgets emit on a Supply; app code taps the Supply and calls `$store.dispatch`.

The one legitimate widget-level subscription is `Border`, which watches `ui.focused-widget` to auto-highlight when a descendant has focus.

BUILDING CUSTOM WIDGETS
=======================

Compose `Selkie::Widget` (leaf) or `Selkie::Container` (has children):

```raku
use Notcurses::Native;
use Notcurses::Native::Plane;
use Selkie::Widget;
use Selkie::Event;

unit class My::Widget does Selkie::Widget;

has Str $.label is required;

method new(*%args --> My::Widget) {
    %args<focusable> //= True;
    callwith(|%args);
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);
    self.apply-style(self.theme.text);
    ncplane_putstr_yx(self.plane, 0, 0, $!label);
    self.clear-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    # ...
    self!check-keybinds($ev);
}
```

Key points:

  * Declare `unit class ... does Selkie::Widget;` or `Selkie::Container`.

  * Always `return without self.plane;` at the top of `render` — the plane is created lazily.

  * End `render` with `self.clear-dirty`.

  * Use `self.theme.xxx` to look up theme styles — never hardcode colors.

  * Use `self.apply-style($style)` to set colors and attributes on the plane.

  * Return `True` from `handle-event` if you consumed the event.

COMMON PITFALLS
===============

`return` in closures
--------------------

`return` in a pointy block (`-E<gt> { ... }`) targets the enclosing routine — which for a handler or subscription closure is usually a method on an outer class. At runtime this throws "Attempt to return outside of immediately-enclosing Routine". Use `if/else` and yield the final expression instead.

Nil decays to Any
-----------------

`Selkie::Store.get-in` returns `Nil` for missing paths, but `my $x = Nil` assigns `Any`. If you pass that to a typed parameter, the bind fails before any `without` guard in the body runs. Use untyped parameters and `.defined` checks for helpers that may receive missing values.

Pixel bleed past plane boundaries
---------------------------------

Notcurses child planes are **not clipped** to their parent's bounds. Pixel-blitted images will extend past containers. `Border` redraws its edges after content to cover bleed; if you compose similar widgets, do the same.

Global keybinds conflicting with input
--------------------------------------

Global keybinds must include a modifier. Bare character keybinds belong on focusable widgets that own the key (e.g. `'a'` on a list view for "add").

`\r\n` is one grapheme
----------------------

In Raku, `"\r\n"` is a single grapheme — `split("\n")` won't match it. Use regex split: `$text.split(/\n/, :v)`. Matters when handling text from Windows sources (pasted content, some JSON blobs).

PHILOSOPHY
==========

Selkie favors a few conventions:

  * **Explicit over implicit**. You build the tree. You own the state. The framework doesn't auto-wire behaviour behind your back.

  * **One way to do things**. There's one layout system, one sizing model, one store pattern. Opinionated by design.

  * **Events in, effects out**. Widgets emit via `Supply`; app code dispatches to the store; handlers return effects; subscriptions derive UI state. Mutations flow one direction.

  * **No lifecycle hooks**. No `componentDidMount`, no `useEffect`. Widgets render when dirty, receive events when focused. That's the whole lifecycle.

AUTHOR
======

Matt Doughty <matt@apogee.guru>

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

