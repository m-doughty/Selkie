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

  * **Safe by default** — all notcurses handles are owned by widgets and freed on destroy. Terminal state is restored on any exit (normal, exception, signal).

  * **Reactive state** — optional centralized store with event dispatch, handlers returning effects, path/computed subscriptions, and opt-in dispatch logging for development.

  * **Composable** — every widget is a role-composed class. Build your own by composing `Selkie::Widget` or `Selkie::Container`.

INSTALLATION
============

```bash
zef install Selkie
```

That's it on supported platforms. No system dependencies, no compiler, no CMake.

How it works
------------

Selkie depends on [Notcurses::Native](https://github.com/m-doughty/Notcurses-Native), which ships prebuilt, self-contained notcurses libraries (with bundled ffmpeg / ncurses / libunistring / libdeflate) for the common platforms. On `zef install` the matching archive is downloaded from GitHub Releases, SHA256-verified against a checksum baked into the distribution, and staged into `resources/`. No system packages are touched.

Supported prebuilt platforms:

  * macOS arm64 (Apple Silicon)

  * Linux x86_64 (glibc — Debian / Ubuntu / Fedora / RHEL / Arch)

  * Linux aarch64 (glibc)

  * Windows x86_64

  * Windows arm64

Falling back to a source build
------------------------------

If you're on a platform not in the list above (Intel Mac, musl Linux, FreeBSD, …), or you set `NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1`, Notcurses::Native compiles notcurses from source via CMake. That path needs the usual native deps:

**Linux (Debian / Ubuntu):**

    sudo apt install \
        cmake pkg-config \
        libncurses-dev libunistring-dev libdeflate-dev \
        libavformat-dev libavcodec-dev libavdevice-dev \
        libavutil-dev libswscale-dev

**Linux (Fedora / RHEL):**

    sudo dnf install cmake pkgconf-pkg-config \
        ncurses-devel libunistring-devel libdeflate-devel ffmpeg-devel

**macOS (Homebrew):**

    brew install cmake pkg-config ffmpeg ncurses libunistring libdeflate

**Windows (MSYS2 UCRT64):**

Install MSYS2 from [https://www.msys2.org/](https://www.msys2.org/), open a **UCRT64** shell, and:

    pacman -S \
        mingw-w64-ucrt-x86_64-cmake \
        mingw-w64-ucrt-x86_64-ninja \
        mingw-w64-ucrt-x86_64-toolchain \
        mingw-w64-ucrt-x86_64-libdeflate \
        mingw-w64-ucrt-x86_64-libunistring \
        mingw-w64-ucrt-x86_64-ncurses \
        mingw-w64-ucrt-x86_64-ffmpeg

The source build takes 5–15 minutes; the prebuilt path takes seconds.

Useful environment variables
----------------------------

  * `NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1` — skip the prebuilt download and always compile from source.

  * `NOTCURSES_NATIVE_BINARY_ONLY=1` — refuse to fall back to source; fail if the prebuilt isn't available for this platform.

  * `NOTCURSES_NATIVE_LIB_DIR=/path/to/dir` — load notcurses from a directory you manage yourself (escape hatch for custom builds).

See [Notcurses::Native's README](https://github.com/m-doughty/Notcurses-Native) for the full set of knobs and the prebuilt-binary security model.

Windows note
------------

On Windows the module installs and loads, but terminal-dependent tests don't run (upstream notcurses limitation). Use Linux or macOS for the full test suite.

DOCUMENTATION
=============

This README covers the framework's concepts, lifecycle, and common patterns. For the per-module API reference — every widget's attributes, methods, and usage examples pulled straight from the source — see [docs/api/index.md](docs/api/index.md). The API pages are regenerated from Pod6 with `raku tools/build-api-docs.raku` and stay in sync with the code by construction.

EXAMPLES
========

The `examples/` directory has eight runnable apps that together demonstrate every widget and store pattern in the framework. Each is self-contained and heavily commented — read them in this order:

  * `counter.raku` — The smallest correct-pattern app. VBox, Text, Button, store handler returning `(db =` ...)>, path subscription, global keybind. Start here.

  * `settings.raku` — A form covering every input widget: TextInput, MultiLineInput, Checkbox, RadioGroup, Select, Button. Plus ConfirmModal, plain Modal, computed subscription for live form summary, and silent setters that sync inputs from store state without feedback loops.

  * `file-viewer.raku` — Split layout with a FileBrowser modal, Image preview, ScrollView for long text. Demonstrates a callback subscription that toggles which preview widget is visible based on the selected file's kind.

  * `tasks.raku` — Todo list with ListView, TextInput, Checkbox filter, ConfirmModal for deletion, Toast notifications, and ScreenManager (list ↔ stats screen).

  * `job-runner.raku` — ProgressBar (both determinate and indeterminate), TextStream log, async store effect for background work, dispatch-effect chaining, frame callback driving animation.

  * `chat.raku` — CardList of variable-height RichText cards, MultiLineInput compose, Border auto-focus highlight, Toast, runtime theme toggle (Ctrl+T).

  * `dashboard.raku` — Tabbed status board showing off the newer widgets: TabBar across three tabs (Servers / Tasks / Logs), Table with sortable columns and custom cell renderers, Spinner in the footer, CommandPalette bound to Ctrl+P, and an inline Sparkline column on the Servers tab rendering each row's recent latency history.

  * `charts.raku` — Showcase of the chart family: Sparkline reactively bound to a store path, LineChart updated via a subscribe-with-callback (live p50 / p99 latencies), BarChart + Histogram + Heatmap + ScatterPlot demonstrating the static archetypes, and a streaming Plot pushing samples into its own native ring buffer.

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

Scope a keybind to a single screen with the `:screen` named argument. It fires only when that screen is the active one, which lets you have different shortcuts per view without reshuffling handlers on every screen switch:

```raku
$app.on-key('ctrl+n', :screen('tasks'), -> $ { create-task });
$app.on-key('ctrl+n', :screen('notes'), -> $ { create-note });
$app.on-key('ctrl+q', -> $ { $app.quit });   # unscoped = everywhere
```

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

MOUSE SUPPORT
=============

Mouse support is enabled by default. `Selkie::App` calls `notcurses_mice_enable` on construction (button + drag events), and the dispatcher routes presses, drags, releases, and scroll-wheel through the same `handle-event` path keystrokes use — but with a different routing rule: **mouse events follow coordinates, not focus**.

Dispatch model
--------------

  * **Keyboard** goes to the focused widget, then ancestors, then global keybinds.

  * **Mouse** goes to the deepest widget under the cursor, then ancestors, then global keybinds.

  * A primary press on a focusable widget gives it focus **before** the event is delivered. Mouse-driven activation matches keyboard-driven activation.

  * **Drag capture**: a press on widget X routes subsequent drag and release events for that button to X regardless of where the cursor is. Scrollbar drags and text-selection drags work even when the cursor leaves the widget.

  * **Modal isolation**: clicks outside the active modal are dropped by default. Pass `:dismiss-on-click-outside` to opt in (`HelpOverlay` uses this; `ConfirmModal` deliberately doesn't).

Per-widget API
--------------

The same shape as `on-key`:

```raku
$widget.on-click: -> $ev {
    say "clicked at row {$widget.local-row($ev)}, col {$widget.local-col($ev)}";
};
$widget.on-click: -> $ev { open-context }, button => 3;   # right-click

$widget.on-scroll: -> $ev {
    given $ev.id {
        when NCKEY_SCROLL_UP   { ... }
        when NCKEY_SCROLL_DOWN { ... }
    }
};

$widget.on-drag: -> $ev { ... };          # press + motion-with-button-held
$widget.on-mouse-down: -> $ev { ... };    # every press
$widget.on-mouse-up:   -> $ev { ... };    # every release
```

`self.local-row($ev)` / `self.local-col($ev)` translate absolute screen coordinates into widget-local cells. `contains-point(y, x)` exposes the same hit-test the framework uses.

Press events carry a `click-count` annotation: 1 = single, 2 = double, 3 = triple. The framework counts a press as a continuation of the previous click when it lands on the same cell with the same button within 300 ms.

What every built-in widget does with the mouse
----------------------------------------------

  * **Button**, **Checkbox** — primary click activates / toggles.

  * **TabBar** — primary click activates the tab under the cursor.

  * **RadioGroup**, **ListView**, **Table** — single-click selects the row; scroll wheel moves the cursor. Table also clicks the column header to cycle sort. ListView and Table fire `on-activate` on double-click.

  * **Select** — click toggles the dropdown; scroll wheel scrolls the open dropdown; click on a dropdown row commits.

  * **TextInput**, **MultiLineInput** — click positions the caret; drag selects; double-click selects the word; triple-click selects the line / buffer; Ctrl+A selects all; Ctrl+C / Ctrl+X emit on `on-copy` / `on-cut` supplies (apps wire the system clipboard themselves via OSC 52 or notcurses paste-buffer).

  * **CardList** — click selects the card under the cursor; scroll wheel moves between cards.

  * **ScrollView**, **TextStream** — scroll wheel scrolls; drag on the scrollbar column drags the thumb.

  * **ConfirmModal**, **CommandPalette**, **FileBrowser** — clicks fall through to the embedded Button / ListView / TextInput, which handle them with their built-in behaviour.

  * **HelpOverlay** — click outside dismisses (it sets `dismiss-on-click-outside`); the embedded Close button still works.

Display-only widgets (Text, RichText, Image, Border, ProgressBar, Spinner, Toast, Legend, all charts) don't react to mouse — Border passes through to its content.

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

`set-items` preserves the current selection by value: if the previously-selected label is still in the new list, the cursor follows it to its new index. Otherwise the cursor is clamped to bounds. Only resets to zero when the list becomes empty. Same behaviour in `RadioGroup` and `Select`.

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

`set-content` destroys the outgoing widget by default. Pass `:!destroy` to swap content while keeping the old widget alive — useful when cycling through persistent views (e.g. a tab strip where each tab is a widget you want to retain state for):

```raku
$border.set-content($view-a);
$border.set-content($view-b, :!destroy);   # $view-a survives
$border.set-content($view-a, :!destroy);   # swap back, still intact
```

Same `:destroy` option is on `Selkie::Widget::Modal.set-content`.

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

Selkie::Widget::Spinner
-----------------------

Tiny animated loading indicator. Drive via `tick` from a frame callback; wall-clock throttled so the rate is independent of how fast your event loop iterates.

```raku
my $spinner = Selkie::Widget::Spinner.new(
    sizing   => Sizing.fixed(2),
    interval => 0.1,                   # 10fps — smooth and calm
);
$app.on-frame: { $spinner.tick };
```

Built-in frame sets: `BRAILLE` (default), `DOTS`, `LINE`, `CIRCLE`, `ARROW`. Or pass a custom array of strings via `frames`.

Selkie::Widget::TabBar
----------------------

Horizontal tab strip with keyboard navigation. Focusable — Left/Right move the active tab, Enter re-emits `on-tab-selected`. Integrates with [Selkie::ScreenManager](Selkie::ScreenManager) via `sync-to-app`, which keeps the bar's active tab synced to `$app.screen-manager.active-screen`.

```raku
my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'inbox',  label => 'Inbox');
$tabs.add-tab(name => 'sent',   label => 'Sent');
$tabs.add-tab(name => 'drafts', label => 'Drafts');

$tabs.on-tab-selected.tap: -> Str $name {
    $app.switch-screen($name);
};
```

Selkie::Widget::CommandPalette
------------------------------

VS-Code-style fuzzy-filtered action launcher. Register commands by label + action, bind to `Ctrl+P`, and you get a searchable palette modal for free.

```raku
my $palette = Selkie::Widget::CommandPalette.new;
$palette.add-command(label => 'New note',     -> { create-note });
$palette.add-command(label => 'Toggle theme', -> { toggle-theme });
$palette.add-command(label => 'Quit',         -> { $app.quit });

my $modal = $palette.build;

$palette.on-command.tap: -> $cmd {
    $app.close-modal;
    $cmd.action.();
};

$app.on-key('ctrl+p', -> $ {
    $palette.reset;
    $app.show-modal($modal);
    $app.focus($palette.focusable-widget);
});
```

Selkie::Widget::Table
---------------------

Scrollable tabular data with typed columns, a header row, sort indicators, cursor navigation, and custom cell rendering. Column widths use the same fixed/percent/flex model as layouts.

```raku
my $table = Selkie::Widget::Table.new(sizing => Sizing.flex);
$table.add-column(name => 'id',     label => 'ID',     sizing => Sizing.fixed(6));
$table.add-column(name => 'name',   label => 'Name',   sizing => Sizing.flex,     :sortable);
$table.add-column(name => 'size',   label => 'Size',   sizing => Sizing.fixed(10), :sortable,
                  render   => -> $b { human-size($b) },
                  sort-key => -> $b { $b.Int });

$table.set-rows([
    { id => 1, name => 'alpha', size => 42_000 },
    { id => 2, name => 'beta',  size => 1_200_000 },
]);

$table.on-activate.tap: -> UInt $idx {
    open-item($table.row-at($idx));
};

$table.sort-by('name');   # cycles asc → desc → unsorted
```

CHART WIDGETS
=============

A family of seven widgets for rendering numeric data, plus three pure-logic helpers. All chart widgets accept either static data (`:data` / `:series`) or a reactive binding to the store (`:store-path` or `subscribe-with-callback` from app code), and all render a centered "No data" placeholder until the first sample arrives — the expected startup state for monitoring dashboards.

The shared primitives
---------------------

The chart widgets share three pure-logic helpers under `Selkie::Plot::*`. You'll occasionally use them directly when composing your own visualisations or when feeding chart widgets pre-computed data.

`Selkie::Plot::Scaler` — linear value→cell mapping. Clamps out-of-domain values, preserves NaN as undef, supports `:invert` for y-axes (so cell 0 holds the maximum value at the top of the screen):

```raku
use Selkie::Plot::Scaler;

my $s = Selkie::Plot::Scaler.linear(min => 0, max => 100, cells => 80);
$s.value-to-cell(50);   # → 40
$s.cell-to-value(20);   # → 25.31...
```

`Selkie::Plot::Ticks` — Heckbert nice-number tick generation, picking labels from `{1, 2, 5} × 10ⁿ`. Returns a tick set whose endpoints may extend slightly past the data range so labels land on round numbers:

```raku
use Selkie::Plot::Ticks;

my $t = Selkie::Plot::Ticks.nice(min => 0, max => 100, count => 5);
$t.values;     # → (0, 20, 40, 60, 80, 100)
$t.labels;     # → ("0", "20", "40", "60", "80", "100")
$t.step;       # → 20
```

`Selkie::Plot::Palette` — colourblind-safe series palettes (`okabe-ito`, `tol-bright`, `tableau-10`) and continuous color ramps (`viridis`, `magma`, `plasma`, `coolwarm`, `grayscale`):

```raku
use Selkie::Plot::Palette;

my @colors = Selkie::Plot::Palette.series('okabe-ito');
my $color  = Selkie::Plot::Palette.sample('viridis', 0.42);   # interpolates
```

Selkie::Widget::Sparkline
-------------------------

Single-row inline chart using the `▁▂▃▄▅▆▇█` block series. Designed to live in tables and status bars, not as a standalone visualisation. Hand- rolled with no native handle, so cheap to embed many instances (e.g. one per Table row).

```raku
use Selkie::Widget::Sparkline;

# Static
my $sl = Selkie::Widget::Sparkline.new(
    data   => [1, 4, 2, 8, 5, 9, 3, 7],
    sizing => Sizing.fixed(1),
);

# Streaming
my $stream = Selkie::Widget::Sparkline.new(sizing => Sizing.fixed(1));
$cpu-supply.tap: -> $sample { $stream.push-sample($sample) };

# Reactive — auto-subscribes to the store path
my $bound = Selkie::Widget::Sparkline.new(
    store-path => <metrics latency-history>,
    min        => 0,
    max        => 100,
    sizing     => Sizing.fixed(1),
);
```

The three modes (`:data` / `:store-path` / streaming) are mutually exclusive. Pin `:min` / `:max` when streaming so the heights don't jitter as new samples shift the auto-range.

Selkie::Widget::Plot
--------------------

Streaming chart wrapping the native `ncuplot` (uint64 samples) / `ncdplot` (num64 samples) widgets in notcurses. The native code handles scaling, blitter selection (braille by default), and incremental rendering — this widget's job is lifecycle management, the Selkie sample-push API, and optional store binding.

```raku
use Selkie::Widget::Plot;

my $cpu = Selkie::Widget::Plot.new(
    type   => 'uint',          # or 'double' for fractional measurements
    min-y  => 0,
    max-y  => 100,
    title  => 'CPU %',
    sizing => Sizing.flex,
);

# Push samples as they arrive
$cpu-supply.tap: -> $pct {
    state $tick = 0;
    $cpu.push-sample($tick++, $pct);
};
```

The native handle is created lazily on the first `render()` after the widget gets a plane. It's destroyed and recreated on resize — sample history is lost, which is fine for a streaming dashboard but worth knowing. For chart history that survives terminal resize, use `Selkie::Widget::LineChart` with a store-held sample buffer instead.

Selkie::Widget::BarChart
------------------------

Categorical bar chart, vertical (default) or horizontal. Each entry is a labelled value; the widget renders one bar per entry with 1/8-cell precision (`▁▂▃▄▅▆▇█` vertically, `▏▎▍▌▋▊▉█` horizontally) so bar heights aren't constrained to whole cells.

```raku
use Selkie::Widget::BarChart;

my $bars = Selkie::Widget::BarChart.new(
    data => [
        { label => 'Q1', value => 1230 },
        { label => 'Q2', value => 1875 },
        { label => 'Q3', value => 2042 },
        { label => 'Q4', value => 1611 },
    ],
    sizing => Sizing.flex,
);

# Horizontal layout
my $hbars = Selkie::Widget::BarChart.new(
    data        => @data,
    orientation => 'horizontal',
    sizing      => Sizing.flex,
);
```

Bar colours come from `:palette` (default `okabe-ito`) cycling through its entries, or from per-bar `color =`> overrides for status indicators where colour means something specific:

```raku
my @data = $tasks.map: -> $t {
    {
        label => $t.name,
        value => $t.duration-ms,
        color => $t.status eq 'failed' ?? 0xCC4444 !! 0x44AA44,
    }
};
```

Y-range auto-derives from `min(0, min-data)` to `max-data`; pass `:min` / `:max` to fix it.

Selkie::Widget::Histogram
-------------------------

Adapter that bins a numeric series into the format `BarChart` expects. Same rendering and styling — just feeds `(label, count)` pairs in.

```raku
use Selkie::Widget::Histogram;

# Equal-width bins
my $h = Selkie::Widget::Histogram.new(
    values => @latency-samples,
    bins   => 20,
    sizing => Sizing.flex,
);

# Custom bin edges (non-uniform — useful for skewed data)
my $log-h = Selkie::Widget::Histogram.new(
    values    => @latency-samples,
    bin-edges => [0, 5, 10, 25, 50, 100, 250, 500, 1000, 5000],
    sizing    => Sizing.flex,
);
```

Bins are **left-closed, right-open** (`[0,10), [10,20)` ...) with the final bin closed-closed (`[90, 100]`) so the maximum sample is always counted. Matches numpy / R / matplotlib defaults.

Selkie::Widget::Heatmap
-----------------------

2D grid coloured by value via a ramp lookup. Each cell renders as `█` with a foreground colour interpolated from the chosen ramp.

```raku
use Selkie::Widget::Heatmap;

my $h = Selkie::Widget::Heatmap.new(
    data   => @grid,            # 2D array of Real
    ramp   => 'viridis',        # or magma, plasma, coolwarm, grayscale
    sizing => Sizing.flex,
);

# Diverging data centred on zero (e.g. correlations)
my $diverging = Selkie::Widget::Heatmap.new(
    data   => @correlation-matrix,
    ramp   => 'coolwarm',
    min    => -1,                # pin the range so 0 stays at the white midpoint
    max    =>  1,
    sizing => Sizing.flex,
);
```

Each input cell becomes one terminal cell — no aspect-ratio compensation. A 10×10 data grid renders tall and narrow because terminal cells are roughly 2:1. Pre-process (e.g. duplicate columns) for square display. NaN cells render with the `text-dim` theme slot so missing data is visually distinct from in-range zero.

Selkie::Widget::ScatterPlot
---------------------------

2D point plot using braille (U+2800-U+28FF) for **sub-cell** resolution: each terminal cell holds a 2×4 dot grid (8 dots per cell), so a 50-cell-wide plot resolves 100 distinct x-positions.

```raku
use Selkie::Widget::ScatterPlot;

# Use Pair (x => y), [x, y] arrays, or hash form per point.
# Bare lists `(x, y)` flatten in array context — don't use them.
my @points = (1..50).map: { (rand * 100) => (rand * 100) };

my $sp = Selkie::Widget::ScatterPlot.new(
    series => [{ label => 'samples', points => @points }],
    sizing => Sizing.flex,
);

# Multi-series with explicit colours
my $sp2 = Selkie::Widget::ScatterPlot.new(
    series => [
        { label => 'group A', points => @group-a, color => 0xE69F00 },
        { label => 'group B', points => @group-b, color => 0x56B4E9 },
    ],
    sizing => Sizing.flex,
);
```

Per-cell colour limitation: a braille codepoint holds all 8 sub-pixels under a single foreground colour. When two series have dots in the same 2×4 cell window, the `:overlap` setting decides who wins — currently only `z-order` is supported (last-drawn series wins). For heavily-overlapping series, prefer faceted layouts (one scatter per series) over single-plot overlay.

Selkie::Widget::LineChart
-------------------------

Static-data multi-series line chart, hand-rolled with the same braille sub-cell resolution as `ScatterPlot`. Composes its own y-axis and legend; supports optional fill-below for area-emphasis charts.

```raku
use Selkie::Widget::LineChart;

# Single series
my $cpu = Selkie::Widget::LineChart.new(
    series => [{ label => 'cpu %', values => @cpu-history }],
    y-min  => 0,
    y-max  => 100,
    sizing => Sizing.flex,
);

# Multi-series with explicit colours and fill
my $cmp = Selkie::Widget::LineChart.new(
    series => [
        { label => 'p50', values => @p50, color => 0xE69F00 },
        { label => 'p99', values => @p99, color => 0xCC4444 },
    ],
    fill-below => True,
    sizing     => Sizing.flex,
);
```

For **streaming** data, use `Selkie::Widget::Plot` instead (it has a native ring buffer better suited to high sample rates). `LineChart` expects you to hand it the full series each time — typically via `set-series` from a `subscribe-with-callback`:

```raku
$app.store.subscribe-with-callback(
    'latency-series',
    -> $s {
        [
            $s.get-in('metrics', 'p50') // [],
            $s.get-in('metrics', 'p99') // [],
        ]
    },
    -> @paths {
        $line-chart.set-series([
            { label => 'p50', values => @paths[0], color => 0x4477AA },
            { label => 'p99', values => @paths[1], color => 0xEE6677 },
        ]);
    },
    $line-chart,
);
```

The same per-cell colour limitation as `ScatterPlot` applies for multi-series crossings. See `examples/charts.raku` for the canonical reactive setup.

Selkie::Widget::Axis and Selkie::Widget::Legend
-----------------------------------------------

Standalone primitives that chart widgets compose internally, exposed for consumers who want to lay out a custom chart by hand. `Axis` renders labelled tick marks along one of the four edges; `Legend` renders a colour-swatch + label row per series.

```raku
use Selkie::Widget::Axis;
use Selkie::Widget::Legend;

my $axis = Selkie::Widget::Axis.new(
    edge       => 'bottom',
    min        => 0,
    max        => 1000,
    tick-count => 5,
    sizing     => Sizing.fixed(2),    # 1 row line + 1 row labels
);

my $legend = Selkie::Widget::Legend.new(
    series => [
        { label => 'cpu',    color => 0xE69F00 },
        { label => 'memory', color => 0x56B4E9 },
    ],
    orientation => 'vertical',
    sizing      => Sizing.fixed(2),
);
```

`Axis.reserved-rows` (for top/bottom) and `Axis.reserved-cols` (for left/right) report the exact dimensions the axis needs given its data range — useful when sizing the parent layout precisely.

Theming chart widgets
---------------------

Six new theme slots cover chart elements:

  * `graph-axis` — axis line and tick marks

  * `graph-axis-label` — tick labels

  * `graph-grid` — optional gridlines

  * `graph-line` — single-series line / sparkline colour

  * `graph-fill` — fill-below colour in line charts

  * `graph-legend-bg` — legend background

All are non-required with defaults derived from existing slots (`text-dim`, `divider`, `border-focused`, `base.bg`), so themes written before the chart widgets shipped keep working. Multi-series chart colours come from `Selkie::Plot::Palette` (not theme slots) so the palette can scale to N series without polluting the theme.

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

Custom widgets that need to wire up a subscription from `on-store-attached` should use the idempotent helpers `once-subscribe` and `once-subscribe-computed`. They track per-id registration so repeated `set-store` calls (e.g. when a widget is reparented) don't create duplicate subscriptions:

```raku
method on-store-attached($store) {
    self.once-subscribe-computed("my-derived-state", -> $s {
        # compute once, subscribe once — safe to call repeatedly
        ...
    });
}
```

Debug logging
-------------

Store state flow is invisible by default. Turn on logging during development to watch events, effects, and subscription fires in real time:

```raku
$app.store.enable-debug;                        # logs to $*ERR
# or:
$app.store.enable-debug(log => open('store.log', :w));

# Later:
$app.store.disable-debug;
```

Output looks like:

    [1776073200.123] dispatch task/add text=Buy milk
    [1776073200.123]   → db: {tasks => [...], next-id => 5}
    [1776073200.124]   sub[task-list] fired: [...]

Each line shows: the dispatched event and its payload, the effects the handler returned, and any subscriptions whose computed value changed. Granularity is configurable — pass `:!dispatches`, `:!effects`, or `:!subscriptions` to silence a category. Overhead when disabled is a single Bool check per hook.

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

TESTING
=======

Widget apps are testable without ever starting notcurses. The `Selkie::Test::*` modules provide synthesis helpers, Supply observation, store assertions, and tree introspection — everything needed to exercise a widget from outside.

Selkie::Test::Keys
------------------

Keystroke synthesis. Build events from the same spec grammar `on-key` accepts:

```raku
use Selkie::Test::Keys;

press-key($widget, 'ctrl+q');          # build + dispatch
press-keys($list, 'down', 'down', 'enter');   # sequence
type-text($input, 'hello world');      # char-by-char
my $ev = key-event('ctrl+shift+a');    # just build, don't dispatch
```

Selkie::Test::Supply
--------------------

Observe what a widget's Supply emits during an action:

```raku
use Selkie::Test::Supply;

my @got = collect-from $btn.on-press, {
    press-key($btn, 'enter');
};

emitted-once-ok $btn.on-press, True, 'Enter fires press', {
    press-key($btn, 'enter');
};

emitted-count-is $list.on-select, 2, 'two moves', {
    press-keys($list, 'down', 'down');
};
```

Selkie::Test::Store
-------------------

Store plumbing for tests — no App required:

```raku
use Selkie::Test::Store;

my $store = mock-store(state => { count => 0, user => { name => 'Alice' } });
dispatch-and-tick($store, 'counter/inc');
is state-at($store, 'count'), 1, 'count incremented';
is state-at($store, 'user', 'name'), 'Alice', 'nested state intact';
```

Selkie::Test::Focus
-------------------

Most focusable widgets gate `handle-event` on `is-focused`. Wrap your test actions in `with-focus` to avoid the boilerplate:

```raku
use Selkie::Test::Focus;

with-focus $input, {
    type-text($input, 'hello');
    press-key($input, 'enter');
};
# Focus released automatically — even if the block throws.
```

Selkie::Test::Tree
------------------

When a widget tree is built by a subscription callback and you don't have direct references, walk it:

```raku
use Selkie::Test::Tree;

my $save-btn = find-widget $root, -> $w {
    $w ~~ Selkie::Widget::Button && $w.label eq 'Save';
};
my @all-buttons = find-widgets $root, * ~~ Selkie::Widget::Button;
contains-widget-ok $root, $my-input, 'input still reachable';
```

Selkie::Test::Snapshot
----------------------

Golden-file snapshot testing. First run saves the widget's rendered output to `t/snapshots/$name.snap`; subsequent runs diff against it.

```raku
use Selkie::Test::Snapshot;

snapshot-ok $my-widget, 'my-widget-default', rows => 10, cols => 40;

# After making an intentional change that affects the render:
#   SELKIE_UPDATE_SNAPSHOTS=1 prove6 -l t
# to accept new output.
```

Uses a real headless notcurses instance (one shared across all snapshots in a test run — notcurses only allows one init per process). Renders the widget, reads cells back via `ncplane_at_yx`, compares against the stored file. No terminal required.

A complete example
------------------

```raku
use Test;
use Selkie::Test::Keys;
use Selkie::Test::Supply;
use Selkie::Test::Focus;
use Selkie::Widget::TextInput;

my $input = Selkie::Widget::TextInput.new;

my @submissions = collect-from $input.on-submit, {
    with-focus $input, {
        type-text($input, 'hello world');
        press-key($input, 'enter');
    };
};

is @submissions.elems, 1, 'submitted once';
is @submissions[0], 'hello world', 'submitted value is correct';

done-testing;
```

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

