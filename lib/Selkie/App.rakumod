=begin pod

=head1 NAME

Selkie::App - The main entry point: event loop, screens, modals, toasts, focus

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Widget::Text;
use Selkie::Sizing;

my $app = Selkie::App.new;

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(
    text   => 'Hello from Selkie',
    sizing => Sizing.fixed(1),
);

$app.add-screen('main', $root);
$app.switch-screen('main');

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;   # blocks until quit

=end code

=head1 DESCRIPTION

C<Selkie::App> is what you construct to start a Selkie program. It owns
the notcurses handle, the reactive store, the screen manager, the
active modal (if any), the toast overlay, the focused widget, and the
event loop.

Your app code:

=item Builds a widget tree
=item Registers it as a screen with C<add-screen>
=item Activates a screen with C<switch-screen>
=item Picks an initial focused widget with C<focus>
=item Registers global keybinds with C<on-key>
=item Starts the loop with C<run>

The loop wakes on a 16ms input timeout (up to 60 Hz). Each wake it
polls for input, dispatches events (to the focused widget, then up the
parent chain, then to global keybinds), runs registered frame
callbacks, ticks the store, processes any queued focus cycling, ticks
the toast, and renders dirty widgets. Idle work is minimized: when
nothing changed, the store's subscription walk and the composite
render to the terminal are both skipped.

C<run> only returns when C<quit> is called or an unhandled exception
reaches the top of the loop. In either case the terminal is restored
before the program exits.

=head2 Theme background

When constructed with a C<theme>, C<Selkie::App> paints the notcurses
standard plane's base cell from C<$theme.base> during init so any
region no widget writes to falls through to the theme background
rather than the terminal's own default. Combined with C<Selkie::Widget>
doing the same per-plane on C<init-plane> / C<set-theme> / each
C<apply-style>, this gives themed backgrounds full-terminal coverage
— no gaps between widgets or at screen edges.

The standard plane itself is exposed via C<stdplane> if you need to
reach it directly (e.g. to paint a custom base cell from application
code).

=head2 Default keybinds

C<Selkie::App> registers these out of the box so you don't have to:

=item C<Tab> / C<Shift-Tab> — cycle focus through focusable descendants
=item C<Esc> — close the active modal (no-op if none)
=item C<Ctrl+Q> — quit the app

Your own C<on-key> registrations don't override these by default — if
you need to, register your handler with a matching spec and call C<quit>
or C<close-modal> yourself.

=head1 LIFECYCLE

Construction calls C<notcurses_init>, enables mouse support, drains any
pending terminal-query responses, and registers the default keybinds.
If C<notcurses_init> fails, construction throws immediately.

An C<END> phaser registered during construction guarantees C<shutdown>
runs even if the program exits abnormally (e.g. an exception before
C<run> is called). This means your terminal is always restored.

C<run> wraps the event loop in a C<CATCH> block. If anything inside the
loop throws, the terminal is restored, the error is printed to STDERR
with a full backtrace, and the process exits with code 1.

=head1 EXAMPLES

=head2 A single-screen app

The simplest pattern. One screen, one focused input, a quit binding:

=begin code :lang<raku>

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Widget::TextInput;
use Selkie::Sizing;

my $app = Selkie::App.new;

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
my $input = Selkie::Widget::TextInput.new(sizing => Sizing.fixed(1));
$root.add($input);

$app.add-screen('main', $root);
$app.switch-screen('main');
$app.focus($input);

$input.on-submit.tap: -> $text { $app.toast("You typed: $text") };

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;

=end code

=head2 Multiple screens

Register each screen with a name; switch between them with
C<switch-screen>. The inactive screens are parked off-screen but keep
their state (widget instances, focus, scroll position):

=begin code :lang<raku>

$app.add-screen('login', $login-root);
$app.add-screen('main',  $main-root);

# Start on login:
$app.switch-screen('login');
$app.focus($login-form.password-input);

# Later, after authentication:
$app.switch-screen('main');
$app.focus($main-root.focusable-descendants.List[0]);

=end code

=head2 A modal dialog

Show a modal to ask the user a question. The modal traps focus — all
keystrokes go to it or its descendants until closed — and C<Esc>
closes it automatically:

=begin code :lang<raku>

use Selkie::Widget::ConfirmModal;

my $cm = Selkie::Widget::ConfirmModal.new;
$cm.build(
    title     => 'Really delete?',
    message   => "This cannot be undone.",
    yes-label => 'Delete',
    no-label  => 'Cancel',
);
$cm.on-result.tap: -> Bool $confirmed {
    $app.close-modal;
    delete-item() if $confirmed;
};

$app.show-modal($cm.modal);
$app.focus($cm.no-button);    # default to the safe button

=end code

=head2 A frame callback for animation

C<on-frame> fires on every iteration of the event loop (~60fps), even
when there's no input. Use it to drive timers, animations, or pull from
an external stream:

=begin code :lang<raku>

$app.on-frame: {
    $progress-bar.tick;           # indeterminate animation
    $chat-view.pull-tokens;       # pull from an LLM stream
};

=end code

=head2 Screen-scoped keybinds

Scope a keybind to one screen by passing C<:screen>. It fires only when
that screen is active:

=begin code :lang<raku>

$app.on-key('ctrl+n', :screen('tasks'), -> $ { create-task });
$app.on-key('ctrl+n', :screen('notes'), -> $ { create-note });
$app.on-key('ctrl+q', -> $ { $app.quit });   # unscoped = every screen

=end code

=head1 SEE ALSO

=item L<Selkie::Widget> — the base role every widget composes
=item L<Selkie::ScreenManager> — multi-screen management (used via C<add-screen> / C<switch-screen>)
=item L<Selkie::Store> — the reactive state store C<Selkie::App> owns
=item L<Selkie::Widget::Modal> — modal dialogs
=item L<Selkie::Event> — the keyboard / mouse event abstraction

=end pod

unit class Selkie::App;

use NativeCall;

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Input;
use Notcurses::Native::Channel;

use Selkie::Widget;
use Selkie::Container;
use Selkie::Event;
use Selkie::Theme;
use Selkie::Sizing;
use Selkie::Layout::VBox;
use Selkie::ScreenManager;
use Selkie::Widget::Modal;
use Selkie::Store;
use Selkie::Widget::Toast;

has NotcursesHandle $!nc;
has NcplaneHandle $!stdplane;

#| The notcurses standard plane — the root of the compositing tree,
#| with the terminal's full dimensions. Exposed for apps that need
#| to set a base cell (fill colour for otherwise-empty cells) so a
#| theme background reaches every corner. Only valid after
#| C<run> has initialised notcurses.
method stdplane(--> NcplaneHandle) { $!stdplane }

#| The theme installed on every screen's root. Defaults to
#| C<Selkie::Theme.default> if not provided to C<.new>.
has Selkie::Theme $.theme;

#| The reactive store owned by this app. Constructed automatically on
#| C<.new>; every screen added to the app gets this store propagated
#| into its widget tree. Subscribe to state paths from widgets via
#| C<self.subscribe(...)>.
has Selkie::Store $.store = Selkie::Store.new;

has Selkie::ScreenManager $!screen-manager = Selkie::ScreenManager.new;
has Selkie::Widget::Modal $!active-modal;
has Selkie::Widget::Toast $!toast;
has Selkie::Widget $!focused;
has Selkie::Widget $!pre-modal-focus;
# Per-screen focus memory: screen name → last-focused widget on that
# screen. Populated lazily on switch-screen when leaving a screen whose
# focused widget is still attached; consulted on switch-screen arrival
# to restore "where you were" instead of snapping focus to first
# focusable every time. Stale entries (widget no longer attached, or
# screen re-registered via add-screen) are pruned lazily rather than
# eagerly to avoid threading App into ScreenManager's remove path.
has %!screen-focus;
has @!global-keybinds;
has @!frame-callbacks;
has Bool $!running = False;
has UInt $!rows = 0;
has UInt $!cols = 0;
has Instant $!last-resize-check = Instant.from-posix(0);
has Supplier $!event-supplier = Supplier.new;

#| The screen manager. Useful for C<.active-screen> and C<.screen-names>
#| — you don't typically need to manipulate it directly, since the
#| C<add-screen> and C<switch-screen> methods on C<Selkie::App> are
#| preferred.
method screen-manager(--> Selkie::ScreenManager) { $!screen-manager }

#| The widget that currently has focus, or C<Nil> if none.
method focused(--> Selkie::Widget) { $!focused }

#| A Supply that emits every event received by the app. Tap this for
#| global event logging, analytics, or cross-cutting behaviour that
#| doesn't fit the per-widget handler model.
method event-supply(--> Supply) { $!event-supplier.Supply }

#| Convenience accessor for the active screen's root container. Equivalent
#| to C<$app.screen-manager.active-root>. Returns C<Nil> if no screen is
#| active.
method root(--> Selkie::Container) { $!screen-manager.active-root }

submethod TWEAK() {
    $!theme //= Selkie::Theme.default;

    my $opts = NotcursesOptions.new(
        flags => NCOPTION_SUPPRESS_BANNERS,
    );
    $!nc = notcurses_init($opts, Pointer);
    die "Failed to initialize notcurses" without $!nc;

    # Disable IXON / IXOFF flow control so Ctrl+Q / Ctrl+S reach the
    # application as keystrokes instead of being eaten by the tty
    # driver as XON / XOFF. notcurses's cbreak mode clears ECHO /
    # ICANON / ICRNL but leaves IXON set — which means on macOS
    # Terminal.app (and other terminals with default IXON on) our
    # Ctrl+Q quit keybind silently doesn't fire. Kitty has IXON off
    # by default so it worked there.
    #
    # notcurses_stop on shutdown restores the original termios state
    # (captured before notcurses touched it), so IXON comes back on
    # automatically when the app exits. No separate restore needed
    # on our side.
    if '/dev/tty'.IO.e {
        # Shell redirect from /dev/tty so stty operates on the real
        # terminal regardless of where our own stdin points (might
        # be a pipe under prove6 / mi6 / tests). 2>/dev/null
        # swallows any error output.
        try shell 'stty -ixon -ixoff < /dev/tty 2>/dev/null';
    }

    notcurses_mice_enable($!nc, NCMICE_BUTTON_EVENT +| NCMICE_DRAG_EVENT);

    $!stdplane = notcurses_stdplane($!nc);
    my uint32 $r = 0;
    my uint32 $c = 0;
    notcurses_stddim_yx($!nc, $r, $c);
    $!rows = $r;
    $!cols = $c;

    # Paint the stdplane's base cell using the theme's `base` style
    # so gaps between widgets fall through to the theme's background
    # instead of the terminal's default. Notcurses composites child
    # planes over the stdplane, and any cell not explicitly written
    # shows the base-cell's channels.
    self!paint-stdplane-base if $!theme.defined;

    # Drain any pending terminal responses (color queries, etc.)
    my $drain-timeout = Timespec.new(tv_sec => 0, tv_nsec => 50_000_000);
    loop {
        my $ni = Ncinput.new;
        my $id = notcurses_get($!nc, $drain-timeout, $ni);
        last if $id == 0;
    }

    self!register-focus-handlers;

    # Safety net for unhandled exceptions between .new and .run. shutdown
    # is idempotent so there's no harm if run's CATCH already ran it.
    my $self = self;
    END { $self.shutdown if $self.defined }
}

# Apply $!theme.base to the stdplane's base cell so cells that no
# widget writes fall through to the theme background instead of
# whatever the terminal was using before. Called from init and from
# live theme swaps via C<set-theme>.
method !paint-stdplane-base() {
    return unless $!theme.defined && $!stdplane;
    my $base = $!theme.base;
    return without $base;
    my uint64 $channels = 0;
    if $base.fg.defined { ncchannels_set_fg_rgb($channels, $base.fg) }
    if $base.bg.defined { ncchannels_set_bg_rgb($channels, $base.bg) }
    ncplane_set_base($!stdplane, ' ', 0, $channels);
}

#|( Swap the active theme at runtime. Updates the app's theme
    attribute, repaints the stdplane base cell, cascades `set-theme`
    to every registered screen's root widget (which in turn walks
    their subtrees), and marks every screen dirty so the next frame
    re-renders with the new palette. App consumers that hold their
    own cached Style objects derived from a theme's slots still need
    to rebuild those — set-theme can't reach closures that copied
    style values at construction time. The primary guarantee here is
    "every plane's base cell and every widget's inherited theme
    updates"; cached styles at the consumer layer are the consumer's
    responsibility. )
method set-theme(Selkie::Theme:D $theme) {
    $!theme = $theme;
    self!paint-stdplane-base;
    for $!screen-manager.screen-names -> $name {
        my $root = $!screen-manager.screen($name);
        if $root.defined {
            $root.set-theme($theme);
            $root.mark-dirty;
        }
    }
}

method !register-focus-handlers() {
    $!store.register-handler('ui/focus', -> $store, %ev {
        (db => { ui => { focused-widget => %ev<widget> } },);
    });

    $!store.register-handler('ui/focus-next', -> $store, %ev {
        (db => { ui => { focus-action => 'next' } },);
    });

    $!store.register-handler('ui/focus-prev', -> $store, %ev {
        (db => { ui => { focus-action => 'prev' } },);
    });

    self.on-key: 'tab', -> $ { $!store.dispatch('ui/focus-next') };
    self.on-key: 'shift+tab', -> $ { $!store.dispatch('ui/focus-prev') };
    self.on-key: 'esc', -> $ { self.close-modal if self.has-modal };
    self.on-key: 'ctrl+q', -> $ { self.quit };
}

# --- Screen management ---

#|( Register a screen under a name. The screen's root container is
    attached to the theme, the store, and the notcurses stdplane, then
    parked either at origin (if it's the first screen added) or off-screen
    (for subsequent screens — C<switch-screen> will move it to origin when
    activated).

    Re-registering a name (common pattern: an overlay screen rebuilt
    each time it opens) discards any stashed per-screen focus from the
    previous incarnation — that widget is about to be destroyed. )
method add-screen(Str:D $name, Selkie::Container $root) {
    $root.set-theme($!theme);
    $root.set-store($!store);
    $root.init-plane($!stdplane, y => 0, x => 0, rows => $!rows, cols => $!cols);
    $root.set-viewport(abs-y => 0, abs-x => 0, rows => $!rows, cols => $!cols);
    if $!screen-manager.screen-names.elems > 0 {
        # Newly-added screens that aren't immediately active get
        # parked off-screen until switch-screen activates them.
        # park() handles sprixel cleanup the way plain reposition
        # can't (see switch-screen for the rationale).
        $root.park;
    }
    $!screen-manager.add-screen($name, $root);
    %!screen-focus{$name}:delete;
}

#|( Activate a registered screen by name. The previously-active screen is
    parked off-screen; the new one is moved to the origin, resized to
    full terminal dimensions, and marked dirty so its entire subtree
    renders fresh on the next frame.

    Focus follows the user: before switching, the outgoing screen's
    focused widget is stashed in per-screen focus memory (if it's still
    attached to that screen's tree). On arrival, the incoming screen's
    last-focused widget is restored — or, if the screen has never been
    visited (or the saved reference went stale), focus lands on the
    first focusable widget in the new tree. Apps don't need to manage
    focus across screen transitions themselves. )
method switch-screen(Str:D $name) {
    my $old-root = self.root;
    my $old-name = $!screen-manager.active-screen;

    # Save outgoing focus before the switch, but only if it's still
    # attached to the outgoing root. A dangling reference isn't worth
    # preserving and will be re-resolved to first-focusable on return.
    if $old-name.defined && $!focused.defined
        && self.widget-attached($!focused, $old-root)
    {
        %!screen-focus{$old-name} = $!focused;
    }

    $!screen-manager.switch-to($name);
    my $new-root = self.root;

    # Park the outgoing screen via park() rather than plain reposition.
    # park() recurses through the subtree and lets widgets that own
    # auxiliary notcurses resources (Image's sprixel especially) clean
    # them up. Without this, sprixels from the outgoing screen
    # continue to display at their old terminal positions, painting
    # over the incoming screen's widgets.
    $old-root.park if $old-root && $old-root !=== $new-root;
    if $new-root {
        $new-root.reposition(0, 0);
        $new-root.resize($!rows, $!cols);
        $new-root.mark-dirty;
    }

    # Restore target screen's focus if we remember it and it's still
    # valid; otherwise auto-focus the first focusable on the new
    # screen. Drop stale entries lazily here — remove-screen doesn't
    # know about %!screen-focus so stale refs can accumulate there.
    my $target = %!screen-focus{$name};
    if $target.defined && self.widget-attached($target, $new-root) {
        self.focus($target);
    } else {
        %!screen-focus{$name}:delete;
        self.focus(self!first-focusable);
    }
}

# --- Terminal title -----------------------------------------------------

#|( Set the terminal window title via OSC 0 ("icon name + window title").
    Writes directly to C</dev/tty> to bypass notcurses's output buffering
    -- the stdplane's double-buffered render path can otherwise stomp
    interleaved escape sequences.

    Handles three common cases:

    =item Bare terminal -- emits C<ESC]0;TITLE BEL>.
    =item Inside tmux (C<$TMUX> set) -- wraps in the DCS passthrough
      (C<ESC Ptmux; ... ESC \\>) so the host terminal actually sees it.
      Requires C<set -g allow-passthrough on> in tmux >= 3.3, which is
      the default from 3.4 onward.
    =item No C</dev/tty> available (tests, piped stdin) -- silently no-op.

    Control characters (ESC, BEL, CR, LF) in C<$title> are stripped before
    emission so a hostile title string can't terminate the sequence early
    or inject further escapes. )
method set-title(Str:D $title) {
    return unless '/dev/tty'.IO.e;
    my $osc = Selkie::App.build-title-osc($title, :tmux(?%*ENV<TMUX>));
    my $tty = try open('/dev/tty', :w);
    if $tty {
        LEAVE { .close with $tty }
        try $tty.print($osc);
    }
}

#|( Build the OSC sequence for a title. Factored out as a class method
    so tests can exercise the sanitisation + tmux-passthrough logic
    without needing a real tty. Public for callers that want to emit
    the sequence elsewhere (logging, snapshot tests, etc). )
method build-title-osc(Str:D $title, Bool :$tmux = False --> Str) {
    # Strip anything that could prematurely terminate the OSC sequence
    # or inject further escapes (ESC, BEL, CR, LF, other C0 / DEL).
    my $safe = $title.subst(/<[ \x00..\x1f \x7f ]>/, '', :g);

    my $osc = "\e]0;$safe\a";
    if $tmux {
        # DCS passthrough: ESC Ptmux; + each ESC doubled + ESC \
        my $inner = $osc.subst("\e", "\e\e", :g);
        $osc = "\ePtmux;{$inner}\e\\";
    }
    $osc;
}

# --- Toast ---

#|( Show a temporary message bar at the bottom of the screen. It auto-dismisses
    after C<$duration> seconds (default 2). The toast overlay is created
    lazily on first call — subsequent toasts reuse the same widget. )
method toast(Str:D $message, Num :$duration = 2e0) {
    without $!toast {
        $!toast = Selkie::Widget::Toast.new;
        $!toast.attach($!stdplane, rows => $!rows, cols => $!cols);
    }
    $!toast.resize-screen($!rows, $!cols);
    $!toast.show($message, :$duration);
}

# --- Modal support ---

#|( Show a modal dialog. The currently-focused widget is remembered and
    restored when the modal closes. While a modal is open, all events are
    routed through it (focus trap); only C<Tab>, C<Shift-Tab>, and C<Esc>
    reach the app's global keybinds. )
method show-modal(Selkie::Widget::Modal $modal) {
    $!pre-modal-focus = $!focused;
    $!active-modal = $modal;
    $modal.set-theme($!theme);
    $modal.set-store($!store);
    $modal.init-plane($!stdplane, y => 0, x => 0, rows => $!rows, cols => $!cols);
    $modal.mark-dirty;

    my @fd = $modal.focusable-descendants.List;
    self.focus(@fd[0]) if @fd;
}

#|( Close the active modal, restore the pre-modal focus target, and mark
    the entire active screen dirty so every widget re-renders over the
    area that was covered. No-op if no modal is open.

    The pre-modal focus target is validated against the live tree
    before restoration — if the widget was destroyed while the modal
    was open (e.g. the modal's action removed the previously-focused
    row from a list), focus falls through to the first focusable on
    the active screen instead of dangling. )
method close-modal() {
    return without $!active-modal;
    $!active-modal.destroy;
    $!active-modal = Selkie::Widget::Modal;
    if $!pre-modal-focus.defined && self.widget-attached($!pre-modal-focus, self.root) {
        self.focus($!pre-modal-focus);
    } else {
        self.focus(self!first-focusable);
    }
    $!pre-modal-focus = Selkie::Widget;
    self!mark-all-dirty(self.root) if self.root;
}

#| True while a modal is currently being displayed.
method has-modal(--> Bool) { $!active-modal.defined }

# --- Keybinds ---

#|( Register a global keybind. The spec is a string matching
    L<Selkie::Event>'s syntax (C<'ctrl+q'>, C<'f1'>, C<'ctrl+shift+a'>, etc).

    Pass C<:screen> to scope the bind to a single named screen — it will
    only fire when that screen is active. Leave C<:screen> unset for a
    truly global bind like Ctrl+Q for quit.

    Global keybinds must include a modifier (Ctrl, Alt, Super) to avoid
    clashing with text input. Bare character binds belong on focusable
    widgets that own the key. )
method on-key(Str:D $spec, &handler, Str :$screen) {
    @!global-keybinds.push: {
        keybind => Keybind.parse($spec, &handler),
        screen  => $screen,
    };
}

#|( Register a callback that fires once per frame (~60 times per second),
    regardless of input. Use this for:

    =item Timer and countdown logic
    =item Animations and indeterminate progress bars (C<$widget.tick>)
    =item Pulling from external streams that aren't tied to user input

    Multiple callbacks can be registered; they run in registration order. )
method on-frame(&callback) {
    @!frame-callbacks.push(&callback);
}

# --- Focus management ---

#|( Move focus to a specific widget. The previously-focused widget's
    C<set-focused(False)> is called (if it has one); the new widget's
    C<set-focused(True)> is called. A C<ui/focus> event is dispatched
    to the store so subscribers (e.g. C<Selkie::Widget::Border>) can
    update their appearance.

    Passing an undefined widget is treated as "focus the first
    focusable on the active surface" — Selkie maintains the invariant
    that C<$!focused> is attached whenever focusable widgets exist.
    The only legitimate "focus: nothing" state is a surface with zero
    focusables, in which case C<$!focused> stays undefined. )
method focus(Selkie::Widget $w) {
    $!focused.set-focused(False) if $!focused.defined && $!focused.can('set-focused');
    my $target = $w.defined ?? $w !! self!first-focusable;
    $!focused = $target;
    $target.set-focused(True) if $target.defined && $target.can('set-focused');
    $!store.dispatch('ui/focus', widget => $target);
}

# Return the first focusable widget on whichever surface currently
# owns input: the active modal if one is open, otherwise the active
# screen. Returns the Widget type object if there are no focusables
# (genuinely nothing to focus) — callers treat that as "focus stays
# undefined."
method !first-focusable(--> Selkie::Widget) {
    my @fd = $!active-modal
        ?? $!active-modal.focusable-descendants.List
        !! $!screen-manager.focusable-descendants.List;
    @fd[0] // Selkie::Widget;
}

# Return the widget-tree root that owns input right now: the active
# modal if any, otherwise the active screen's root. Used by
# widget-attached callers to check whether a focus candidate is still
# in the live tree.
method !focus-root() {
    $!active-modal.defined ?? $!active-modal !! $!screen-manager.active-root;
}

#|( True iff walking up C<$w>'s parent chain reaches C<$root>. Used
    internally to validate that a saved focus reference (in
    C<%!screen-focus> or C<$!pre-modal-focus>) is still attached to
    the live tree before we try to restore it. O(tree depth); cheap.

    Public (rather than private with a leading bang) so tests can
    exercise the logic via the type object — C<Selkie::App.widget-attached(...)>
    works without constructing an App instance (which would require
    C<notcurses_init>). Apps rarely need to call this directly. )
method widget-attached(Selkie::Widget $w, $root --> Bool) {
    return False without $w;
    return False without $root;
    my $node = $w;
    while $node.defined {
        return True if $node === $root;
        $node = $node.parent;
    }
    False;
}

#|( Verify that C<$!focused> is still attached to the input-owning
    surface (the active modal, or the active screen). If it's
    dangling — its container was removed, its screen was destroyed,
    etc. — re-focus the first focusable on the surface. No-op when
    focus is already valid, or when nothing was focused to begin with.

    Called automatically at the top of every event-loop iteration.
    Exposed as a public method mainly so tests can drive the guard
    directly without spinning C<run> — apps don't normally need to
    call it. )
method check-focus-invariant() {
    return unless $!focused.defined;
    return if self.widget-attached($!focused, self!focus-root);
    self.focus(self!first-focusable);
}

#| Move focus to the next focusable widget in the tree. Wraps around at
#| the end. Bound to C<Tab> by default.
method focus-next() {
    self!do-focus-cycle(1);
}

#| Move focus to the previous focusable widget. Wraps around at the
#| beginning. Bound to C<Shift-Tab> by default.
method focus-prev() {
    self!do-focus-cycle(-1);
}

method !process-focus-actions() {
    my $action = $!store.get-in('ui', 'focus-action');
    if $action.defined {
        $!store.assoc-in('ui', 'focus-action', value => Nil);
        given $action {
            when 'next' { self!do-focus-cycle(1) }
            when 'prev' { self!do-focus-cycle(-1) }
        }
    }
}

method !do-focus-cycle(Int $direction) {
    my @focusable = $!active-modal
        ?? $!active-modal.focusable-descendants.List
        !! $!screen-manager.focusable-descendants.List;
    return unless @focusable;

    if $!focused.defined {
        my $idx = @focusable.first(* === $!focused, :k);
        if $idx.defined {
            self.focus(@focusable[($idx + $direction) % @focusable.elems]);
        } else {
            self.focus(@focusable[$direction > 0 ?? 0 !! *-1]);
        }
    } else {
        self.focus(@focusable[$direction > 0 ?? 0 !! *-1]);
    }
}

# --- Lifecycle ---

#| Signal the event loop to exit. C<run> returns after the current frame
#| completes; the terminal is restored by C<shutdown>.
method quit() {
    $!running = False;
}

#|( Start the event loop. Blocks until C<quit> is called or an unhandled
    exception bubbles up. The loop wakes on a 16ms input timeout (up
    to 60 Hz) and handles: input polling, event dispatch, frame
    callbacks, store tick, focus action processing, toast tick, and
    rendering.

    Idle work is minimized on each dimension: resize polling is
    throttled to ~12 Hz, the store tick only walks subscriptions when
    events were processed, and the renderer only composites to the
    terminal when a widget actually rendered (or the toast just
    auto-dismissed). A static screen produces near-zero CPU.

    The loop body is wrapped in a C<CATCH> block: any thrown exception
    triggers an orderly shutdown, prints a backtrace to STDERR, and
    exits the process with status 1. )
method run() {
    $!running = True;
    self!render-frame;

    my $timeout = Timespec.new(tv_sec => 0, tv_nsec => 16_000_000);
    while $!running {
        # Belt-and-braces: if the focused widget got detached between
        # ticks (Container::remove, a screen destroyed while parked,
        # a focus-holder torn down by a subscription callback), rebind
        # focus before we try to dispatch input into a dangling ref.
        self.check-focus-invariant;

        my $ni = Ncinput.new;
        my $id = notcurses_get($!nc, $timeout, $ni);
        if $id > 0 {
            my $ev = Selkie::Event.from-ncinput($ni);
            $!event-supplier.emit($ev);
            self!dispatch-event($ev);
        }
        # Poll stdplane dimensions at ~12 Hz. notcurses doesn't
        # reliably emit NCKEY_RESIZE through the input queue on all
        # platforms — on macOS in particular, render can absorb a
        # SIGWINCH internally (resizing stdplane) without the input
        # thread ever raising a resize event. Polling ensures we
        # catch every dim change regardless of whether the input
        # path delivered a ResizeEvent. 12 Hz (83 ms) is fast enough
        # that the UI reflow feels instant and slow enough that the
        # syscall stops being a measurable idle-CPU cost.
        self!maybe-check-terminal-resize;

        .() for @!frame-callbacks;
        $!store.tick;
        self!process-focus-actions;
        # Toast.tick returns True when visibility just flipped to False
        # this tick (the duration expired). The composited frame still
        # has the toast painted, so we need a fresh composite render to
        # erase it — force it through even if no widget is dirty.
        my Bool $toast-hid = $!toast ?? $!toast.tick !! False;
        self!render-frame(:force($toast-hid));
    }

    self.shutdown;

    CATCH {
        default {
            self.shutdown;
            $*ERR.say("Selkie crashed: {.message}");
            $*ERR.say(.backtrace.full);
            exit 1;
        }
    }
}

method !dispatch-event(Selkie::Event $ev) {
    return if $ev.input-type == NCTYPE_RELEASE;

    if $ev.event-type ~~ ResizeEvent {
        self!check-terminal-resize;
        return;
    }

    if $!active-modal {
        if $!focused.defined {
            my $widget = $!focused;
            while $widget.defined && $widget !=== $!active-modal {
                if $widget.handle-event($ev) {
                    return;
                }
                $widget = $widget.parent;
            }
        }
        return if $!active-modal.handle-event($ev);
        for @!global-keybinds -> %entry {
            next if %entry<screen>.defined
                 && %entry<screen> ne ($!screen-manager.active-screen // '');
            if %entry<keybind>.matches($ev) {
                %entry<keybind>.handler.($ev);
                return;
            }
        }
        return;
    }

    self!bubble-event($ev);
}

method !bubble-event(Selkie::Event $ev --> Bool) {
    my $widget = $!focused;
    while $widget.defined {
        return True if $widget.handle-event($ev);
        $widget = $widget.parent;
    }

    my $active-screen = $!screen-manager.active-screen // '';
    for @!global-keybinds -> %entry {
        next if %entry<screen>.defined && %entry<screen> ne $active-screen;
        if %entry<keybind>.matches($ev) {
            %entry<keybind>.handler.($ev);
            return True;
        }
    }

    False;
}

method !mark-all-dirty(Selkie::Widget $w) {
    $w.mark-dirty;
    if $w ~~ Selkie::Container {
        for $w.children -> $child {
            self!mark-all-dirty($child);
        }
    }
    if $w.can('content') && $w.content.defined {
        self!mark-all-dirty($w.content);
    }
}

#|( Check whether the terminal has been resized and, if so, propagate
    new dimensions through the widget tree and force a full terminal
    re-sync. Called every ~83ms from the main loop (via
    C<!maybe-check-terminal-resize>) because notcurses doesn't reliably
    emit C<NCKEY_RESIZE> through the input queue on every platform —
    macOS in particular. Also called synchronously by C<!dispatch-event>
    when a real C<ResizeEvent> arrives, which should not be rate-limited.

    No-op when dims haven't changed; cheap. )
method !check-terminal-resize() {
    my uint32 $r = 0;
    my uint32 $c = 0;
    notcurses_stddim_yx($!nc, $r, $c);
    return if $r == $!rows && $c == $!cols;

    $!rows = $r;
    $!cols = $c;

    # Propagate dims synchronously through all screens (including
    # inactive ones — they'd otherwise render at stale dims when
    # switched to later) and any active modal/toast. handle-resize
    # cascades through containers so leaf widgets know their new
    # dims before any render.
    $!screen-manager.handle-resize($!rows, $!cols);
    $!active-modal.handle-resize($!rows, $!cols) if $!active-modal;
    $!toast.handle-resize($!rows, $!cols)       if $!toast;

    # Mark-dirty cascade — handle-resize short-circuits on unchanged
    # dims, so we force everyone to re-render even if their
    # allocation happened to match.
    self!mark-all-dirty(self.root)    if self.root;
    self!mark-all-dirty($!active-modal) if $!active-modal;

    # Render the new frame to widget planes NOW, synchronously, so
    # the terminal gets updated immediately rather than waiting for
    # the next loop iteration's bottom-of-loop render (which would
    # show stale content until the user typed something).
    self!render-frame;

    # notcurses_refresh forces the terminal to re-sync with the
    # just-rendered frame — discards notcurses's internal "what's on
    # screen" state and re-emits every cell. Without this, the
    # frame-diff can miss cells whose composited value happens to
    # match pre-resize even though the planes behind them have
    # shifted (duplicated chrome, missing titles, etc).
    my uint32 $rr = 0;
    my uint32 $cc = 0;
    notcurses_refresh($!nc, $rr, $cc);
}

#|( Rate-limit wrapper around C<!check-terminal-resize>. Called from
    the main loop every frame, but only lets the underlying check run
    at most once per ~83ms (~12 Hz). See C<!check-terminal-resize> for
    why we poll at all. )
method !maybe-check-terminal-resize() {
    return if now - $!last-resize-check < 1/12;
    $!last-resize-check = now;
    self!check-terminal-resize;
}

#|( Render any dirty parts of the widget tree and, if anything actually
    rendered, composite the frame to the terminal via C<notcurses_render>.

    The composite is B<gated on whether any widget rendered this frame>.
    On a static screen — no dirty widgets, no visible toast — the frame
    is a no-op: we skip the compositor, the terminal diff, and the pty
    writes that would otherwise run ~60 Hz while idle.

    The C<:force> flag overrides the gate. It's set by the main loop
    when C<Toast.tick> reports that visibility just flipped off: the
    previous composite still shows the toast, so we need one more
    render to erase it even though no widget is dirty. )
method !render-frame(Bool :$force = False) {
    my Bool $any-rendered = False;
    my $root = self.root;
    if $root && $root.is-dirty {
        $root.render;
        $any-rendered = True;
    }
    if $!active-modal && $!active-modal.is-dirty {
        $!active-modal.render;
        $any-rendered = True;
    }
    if $!toast && $!toast.is-visible {
        $!toast.render;
        $any-rendered = True;
    }
    notcurses_render($!nc) if $any-rendered || $force;
}

#|( Shut down notcurses and destroy the active modal and screen manager.
    Idempotent — safe to call multiple times. Usually you don't call this
    directly; the event loop's CATCH, the END phaser, or C<DESTROY>
    takes care of it. )
method shutdown() {
    $!active-modal.destroy if $!active-modal;
    $!active-modal = Selkie::Widget::Modal;
    $!screen-manager.destroy;
    if $!nc {
        notcurses_stop($!nc);
        $!nc = NotcursesHandle;
    }
}

method DESTROY() {
    self.shutdown if $!nc;
}
