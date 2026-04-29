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

Modals stack. Calling C<show-modal> while another modal is already open
pushes the new modal on top — useful for, say, a confirm dialog opened
from inside an editor. C<close-modal> pops the topmost modal, and the
previous modal becomes active again with all its keybinds intact and
its pre-modal-focus restored. Repeat C<close-modal> to drain the stack.

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

=head2 Reacting to terminal resizes

C<on-resize> fires whenever Selkie's polling detects a change in the
host terminal's dimensions. Multiple callbacks are supported and run in
registration order, after the widget tree has been re-laid-out and the
new frame has been composited. Use this for cleanup that has to span
the whole tree on a resize — most commonly, parking pixel-blitter
sprixels (Kitty / Sixel) so they re-blit at their new positions on the
next frame:

=begin code :lang<raku>

$app.on-resize: -> UInt $rows, UInt $cols {
    park-every-image-in($app.screen-manager.active-root);
};

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
# Modal stack — each `show-modal` pushes; `close-modal` pops the top.
# The "active modal" (input-owning, rendered on top) is always
# `@!modal-stack.tail`. Selkie supports nested modals (e.g. a confirm
# dialog opened from inside an editor) — popping the inner modal
# restores the outer one with all its keybinds intact.
has Selkie::Widget::Modal @!modal-stack;
# Parallel stack of pre-modal focus targets. `@!pre-modal-focus-stack[i]`
# is the widget that was focused right before `@!modal-stack[i]` opened;
# popping the modal restores the matching entry. We do NOT use a single
# slot because nested modals each have their own "where to return focus"
# context.
has Selkie::Widget @!pre-modal-focus-stack;
has Selkie::Widget::Toast $!toast;
has Selkie::Widget $!focused;
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
has @!resize-callbacks;
has Bool $!running = False;
has UInt $!rows = 0;
has UInt $!cols = 0;
has Instant $!last-resize-check = Instant.from-posix(0);

#|( Set asynchronously by our SIGWINCH handler when the terminal is
    resized. Consumed by C<!maybe-check-terminal-resize>, which clears
    the flag and bypasses the 12 Hz rate-limit so the new dims propagate
    on the very next loop iteration. Atomic because the signal callback
    runs on whatever thread libuv dispatches to, while the main loop
    reads it from the application thread. )
has atomicint $!resize-pending = 0;

#|( Tap on Raku's signal(SIGWINCH) Supply. Stored so C<shutdown> can
    close it cleanly — without explicit close, the tap keeps the App
    object alive past shutdown via the Supply's subscriber list, and
    SIGWINCH after shutdown would still try to fire the (now invalid)
    handler. )
has $!resize-tap;

has Supplier $!event-supplier = Supplier.new;

#|( Hot-rate frame budget in Hz. The main loop caps itself at this
    rate while anything is happening; the idle ladder then steps
    down (to 30 / 12 / 4 Hz) after periods of inactivity. Defaults
    to 60 Hz — enough for smooth typing and scrolling without
    burning battery on passive sits. Apps doing terminal video
    playback, high-refresh animations, or live plot rendering can
    bump this higher — notcurses itself supports video, so 120 Hz+
    is a legitimate use case for that flavour of app.

    This is a CEILING, not a floor: the loop sleeps at least
    C<1 / $hot-hz> seconds between frames, but may sleep longer
    when the idle ladder has ramped down. )
has Num $.hot-hz = 60e0;

#|( Path to a file that receives everything that would normally hit
    stderr while the app is running — Raku warnings
    (C<Use of uninitialized value …>), runtime failures logged via
    C<note>, C-level libraries writing to stderr, notcurses internal
    diagnostics, etc.

    Without this, warnings splat into the TUI compositor's cell grid
    and produce visible garbage that stays on screen until the next
    full repaint — a TUI can't share stderr with its own drawing
    surface.

    When set, C<Selkie::App> uses C<dup2(2)> on construction to point
    file descriptor 2 at this file (append mode); the saved copy of
    the original stderr is restored on C<shutdown>. Parent directory
    is auto-created. A new "=== session …" banner is written at the
    top of each run so long-lived log files stay navigable.

    Leave as C<Str> (the type object) to disable the redirect — then
    stderr goes where it would normally. )
has Str $.error-log;
has Int $!saved-stderr-fd;
has IO::Handle $!error-log-handle;

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

    # Redirect stderr to the log file BEFORE notcurses_init so any
    # banner text or terminal-capability probe output notcurses emits
    # during startup lands in the log instead of fighting with the
    # splash screen. C<NCOPTION_SUPPRESS_BANNERS> below covers the
    # intentional banner, but notcurses still writes diagnostics on
    # some terminals at init.
    self!install-error-log if $!error-log.defined && $!error-log.chars > 0;

    # NCOPTION_NO_WINCH_SIGHANDLER: we install our own SIGWINCH handler
    # via Raku's C<signal()> Supply (below). Letting notcurses install
    # one too creates a sigaction race — whoever installs second wins,
    # and on macOS notcurses's handler can absorb SIGWINCH without
    # waking our event loop, leaving stale dims until the user types.
    # Owning the signal here means we always wake; we forward the dim
    # re-query into notcurses via C<notcurses_refresh> in
    # C<!check-terminal-resize>.
    my $opts = NotcursesOptions.new(
        flags => NCOPTION_SUPPRESS_BANNERS +| NCOPTION_NO_WINCH_SIGHANDLER,
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

    # Install our SIGWINCH handler. The tap fires on whatever thread
    # libuv dispatches to (not the main loop's thread), so we use an
    # atomic CAS to set the flag — the main loop reads it from
    # C<!maybe-check-terminal-resize> on every iteration. Setting the
    # flag also wakes the chunked sleep in C<run> within ~16ms, so a
    # resize during deep idle (when the loop sleeps for up to 250ms)
    # is picked up almost immediately instead of waiting for input.
    $!resize-tap = signal(SIGWINCH).tap: { cas($!resize-pending, 0, 1) };

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
    reach the app's global keybinds.

    Modals stack: calling C<show-modal> while another modal is already
    open pushes the new modal on top. C<close-modal> pops the top, so the
    previous modal becomes active again with all its keybinds intact.
    This is how a confirm dialog opened from inside an editor returns
    focus to the editor when dismissed. )
method show-modal(Selkie::Widget::Modal $modal) {
    @!pre-modal-focus-stack.push($!focused);
    @!modal-stack.push($modal);
    $modal.set-theme($!theme);
    $modal.set-store($!store);
    $modal.init-plane($!stdplane, y => 0, x => 0, rows => $!rows, cols => $!cols);
    $modal.mark-dirty;

    my @fd = $modal.focusable-descendants.List;
    self.focus(@fd[0]) if @fd;
}

#|( Close the topmost modal, restore the matching pre-modal focus
    target, and mark the now-revealed surface dirty so it re-renders
    over the area the closing modal covered. No-op if no modal is open.

    With nested modals, popping the top reveals the modal underneath —
    that becomes the new active modal, and focus is restored to the
    widget inside it that had focus right before the popped modal
    opened. When the stack drains to empty, focus restores against the
    active screen.

    The pre-modal focus target is validated against the live tree
    before restoration — if the widget was destroyed while the modal
    was open (e.g. the modal's action removed the previously-focused
    row from a list), focus falls through to the first focusable on
    the now-active surface instead of dangling. )
method close-modal() {
    return without @!modal-stack;
    my $closed = @!modal-stack.pop;
    my $restore = @!pre-modal-focus-stack.pop;
    $closed.destroy;

    # The "input-owning surface" we restore focus against depends on
    # whether any modal remains: top-of-stack if the stack is non-empty,
    # the screen root otherwise. !focus-root reads the same source.
    my $root = self!focus-root;
    if $restore.defined && self.widget-attached($restore, $root) {
        self.focus($restore);
    } else {
        self.focus(self!first-focusable);
    }
    # Mark the revealed surface dirty so it re-paints over the area
    # the popped modal covered. Without a stack the screen does this;
    # with one, the new top modal needs the kick instead (its plane
    # was below the destroyed one and notcurses won't redraw it
    # otherwise).
    if @!modal-stack {
        self!mark-all-dirty(@!modal-stack.tail);
    } else {
        self!mark-all-dirty(self.root) if self.root;
    }
}

#| True while at least one modal is currently being displayed.
method has-modal(--> Bool) { ?@!modal-stack }

# Top-of-stack accessor. Returns the type object when the stack is
# empty so callers can keep their existing C<if $!active-modal> /
# C<.defined> idiom; this preserves the pre-stack code paths in
# event-routing, render, and resize without wholesale rewrites.
method !active-modal() {
    @!modal-stack ?? @!modal-stack.tail !! Selkie::Widget::Modal;
}

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

#|( Register a callback that fires when the terminal is resized.
    Receives the new C<($rows, $cols)> as positional arguments. Fires
    after the widget tree has been re-laid-out and the post-resize
    frame composited, so callbacks can safely walk the live tree and
    take action against the new dimensions.

    The primary use case is bitmap (Kitty / Sixel) sprixel cleanup:
    pixel blitters paint directly to the terminal and don't follow
    plane reflows, so a sidebar avatar painted in column 3 stays in
    column 3 after a horizontal resize even if its plane has moved.
    Parking the C<Selkie::Widget::Image> in the resize callback drops
    the stale sprixel; the next render rebuilds it at the new
    position. )
method on-resize(&callback) {
    @!resize-callbacks.push(&callback);
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
    my $top = self!active-modal;
    my @fd = $top.defined
        ?? $top.focusable-descendants.List
        !! $!screen-manager.focusable-descendants.List;
    @fd[0] // Selkie::Widget;
}

# Return the widget-tree root that owns input right now: the topmost
# modal if any, otherwise the active screen's root. Used by
# widget-attached callers to check whether a focus candidate is still
# in the live tree.
method !focus-root() {
    my $top = self!active-modal;
    $top.defined ?? $top !! $!screen-manager.active-root;
}

#|( True iff walking up C<$w>'s parent chain reaches C<$root>. Used
    internally to validate that a saved focus reference (in
    C<%!screen-focus> or C<@!pre-modal-focus-stack>) is still attached to
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
    my $top = self!active-modal;
    my @focusable = $top.defined
        ?? $top.focusable-descendants.List
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

    # Scale the notcurses_get timespec to match the hot frame budget
    # so platforms where it DOES block (Linux) still cap at the right
    # rate. On macOS it returns immediately regardless; the sleep
    # fallback below is what actually caps the cadence there.
    my Int $hot-ns = (1_000_000_000 / $!hot-hz).Int;
    my $timeout = Timespec.new(tv_sec => 0, tv_nsec => $hot-ns);

    # --- Idle ladder ---------------------------------------------------
    # Stay at the hot rate while anything's happening; ramp down the
    # tick rate when idle so a backgrounded TUI stops burning battery
    # as if it were still in-focus.
    #
    # Thresholds (seconds since last "activity"):
    #   0-30  s : hot rate (default 60 Hz, configurable via $!hot-hz)
    #   30-60 s : 30 Hz
    #   60-120s : 12 Hz
    #   120s +  : 4 Hz
    #
    # "Activity" = input event, resize, store event processed by any
    # registered handler, or toast visibility change. Passive store
    # reads don't count.
    #
    # The ladder caps at 4 Hz / 250 ms so snap-back from deep idle
    # still feels near-instant on the first keystroke: worst-case
    # input latency after 2+ minutes of idle is one 250 ms sleep.
    my Num $hot-budget  = (1e0 / $!hot-hz.Num);  # e.g. 16.67 ms at 60 Hz
    my constant IDLE-HALF     = 1e0 / 30e0;      # 30 Hz = ~33 ms
    my constant IDLE-QUARTER  = 1e0 / 12e0;      # 12 Hz = ~83 ms
    my constant IDLE-DEEP     = 1e0 /  4e0;      #  4 Hz = 250 ms
    my Instant $last-activity = now;
    # The ladder may only SLOW the tick rate, never speed it up. Apps
    # that set a slow hot-hz (say 10 Hz for a low-motion tool on a
    # battery-constrained device) would otherwise paradoxically
    # accelerate at idle because the idle tiers are faster than the
    # hot rate. C<max($hot, $idle)> clamps each tier to at-least-hot.
    sub pick-budget(Instant $last-act, Num $hot --> Num) {
        my Num $since = (now - $last-act).Num;
        my Num $ideal = do given $since {
            when * <  30e0 { $hot         }
            when * <  60e0 { IDLE-HALF    }
            when * < 120e0 { IDLE-QUARTER }
            default        { IDLE-DEEP    }
        };
        max($ideal, $hot);
    }
    while $!running {
        # Belt-and-braces: if the focused widget got detached between
        # ticks (Container::remove, a screen destroyed while parked,
        # a focus-holder torn down by a subscription callback), rebind
        # focus before we try to dispatch input into a dangling ref.
        self.check-focus-invariant;

        # notcurses_get(...) with a timespec SHOULD block for up to
        # 16 ms. On macOS (measured 2026-04-21) it returns almost
        # immediately — ~378k calls per second — turning this loop
        # into a hot spin that pegs a CPU core. We can't rely on
        # notcurses for the frame cadence. Instead: measure how long
        # the call actually took; if it was short-circuit-fast, sleep
        # the remainder of the frame budget so we truly idle at 60 Hz.
        my Instant $frame-start = now;
        my Bool $activity = False;

        my $ni = Ncinput.new;
        my $id = notcurses_get($!nc, $timeout, $ni);
        if $id > 0 {
            $activity = True;
            my $ev = Selkie::Event.from-ncinput($ni);
            $!event-supplier.emit($ev);
            self!dispatch-event($ev);

            # Drain any further pending input with the non-blocking
            # variant — handles paste / burst typing / held-key
            # autorepeat that queues characters faster than a single
            # 16 ms frame can dispatch one-per-tick.
            #
            # Paste batching: the per-char dispatch path runs the
            # focused widget's handle-event, which on text inputs
            # does an O(n) buffer rebuild — making a paste of n chars
            # cost O(n²) total, which truncates real pastes by hitting
            # whatever cap we set on the drain. Instead, accumulate
            # consecutive paste-eligible events (printable chars or
            # newline / carriage return, no Ctrl / Alt / Super
            # modifiers) into a List, then flush them as a single
            # `insert-text(Str)` call on the focused widget at the
            # end of the burst. That's one buffer rebuild per paste,
            # not one per character. List-of-strings accumulator
            # avoids O(n²) string concat building the batch itself.
            #
            # The first event (from the blocking get above) is always
            # dispatched normally so single-key actions — Enter to
            # submit, Tab to cycle focus — keep their per-event
            # semantics. Only subsequent events in the same drain
            # burst get batched.
            #
            # Wall-clock cap of 200 ms (~12 frames at 60 Hz) bounds
            # pathological infinite-input sources without truncating
            # realistic pastes. The drain itself is now cheap (no
            # per-char widget work), so most pastes finish in well
            # under a frame.
            my Instant $drain-start = $frame-start;
            my @paste-batch;
            loop {
                my $ni2 = Ncinput.new;
                my $id2 = notcurses_get_nblock($!nc, $ni2);
                last if $id2 == 0 || $id2 == -1;
                my $ev2 = Selkie::Event.from-ncinput($ni2);

                if self!is-paste-char($ev2)
                   && $!focused.defined
                   && $!focused.^can('insert-text') {
                    @paste-batch.push($ev2.char);
                } else {
                    if @paste-batch {
                        self!flush-paste-batch(@paste-batch.join(''));
                        @paste-batch = ();
                    }
                    $!event-supplier.emit($ev2);
                    self!dispatch-event($ev2);
                }
                last if (now - $drain-start).Num > 0.2e0;
            }
            if @paste-batch {
                self!flush-paste-batch(@paste-batch.join(''));
            }
        }
        # Drain a pending SIGWINCH if our signal tap (installed in
        # TWEAK) flagged one since the last loop iteration. Cheap —
        # it's an atomic CAS and a branch when no resize is pending,
        # one full notcurses_refresh + cascade when there is. The
        # signal-driven wake is what makes resizes show up without
        # the user typing on macOS, where notcurses absorbs SIGWINCH
        # internally without queueing a ResizeEvent through input.
        $activity = True if self!maybe-check-terminal-resize;

        .() for @!frame-callbacks;
        $activity = True if $!store.tick;
        self!process-focus-actions;
        # Toast.tick returns True when visibility just flipped to False
        # this tick (the duration expired). The composited frame still
        # has the toast painted, so we need a fresh composite render to
        # erase it — force it through even if no widget is dirty.
        my Bool $toast-hid = $!toast ?? $!toast.tick !! False;
        $activity = True if $toast-hid;
        self!render-frame(:force($toast-hid));

        # Bump the activity timestamp so the idle ladder stays hot.
        # Any of: input event, resize detected, store event dispatched
        # to a handler, toast visibility flip. Passive store reads
        # don't count.
        $last-activity = now if $activity;

        # Idle-remainder sleep, budget chosen from the ladder above.
        # When idle > 10 s we drop to 4 Hz (250 ms sleeps) — low enough
        # battery cost to barely register; high enough that snap-back
        # latency on the first keystroke feels near-instant. Everything
        # below ~1 s idle stays at 60 Hz.
        #
        # The sleep is broken into 16 ms chunks so a SIGWINCH-driven
        # resize (which sets C<$!resize-pending> via the signal tap
        # installed in TWEAK) wakes the loop within roughly one frame
        # rather than waiting for the full budget to elapse. Without
        # this, a resize during deep idle would sit unnoticed for up
        # to 250 ms — the user-visible "I have to press a key for
        # the resize to take effect" symptom on macOS, where notcurses
        # alone doesn't reliably surface SIGWINCH through the input
        # queue.
        my Num $budget  = pick-budget($last-activity, $hot-budget);
        my Num $elapsed = (now - $frame-start).Num;
        my Num $remaining = $budget - $elapsed;
        while $remaining > 0e0 {
            last if $!resize-pending;
            my Num $chunk = $remaining min 0.016e0;
            sleep $chunk;
            $remaining -= $chunk;
        }
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

#|( True when an input event is a "paste-eligible" character — a plain
    printable key with no Ctrl / Alt / Super modifier. Used by the
    drain loop to decide what to accumulate into the paste batch.
    Mod-Shift is allowed because capital letters arrive with it set
    and must be batched alongside everything else. )
method !is-paste-char(Selkie::Event $ev --> Bool) {
    return False unless $ev.event-type ~~ KeyEvent;
    return False unless $ev.input-type == NCTYPE_PRESS
                     || $ev.input-type == NCTYPE_REPEAT
                     || $ev.input-type == NCTYPE_UNKNOWN;
    return False if $ev.has-modifier(Mod-Ctrl)
                 || $ev.has-modifier(Mod-Alt)
                 || $ev.has-modifier(Mod-Super);
    return False unless $ev.char.defined && $ev.char.chars == 1;
    my $ord = $ev.char.ord;
    $ord >= 32 || $ord == 10 || $ord == 13;
}

#|( Apply an accumulated paste batch to the focused widget's
    `insert-text` method. Caller has already verified that the
    focused widget supports the method, so this is a single dispatch
    plus one O(n) buffer rebuild — total cost O(n) for the whole
    paste, not O(n²) the per-char path would incur. )
method !flush-paste-batch(Str:D $text) {
    return if $text.chars == 0;
    return unless $!focused.defined && $!focused.^can('insert-text');
    $!focused.insert-text($text);
}

method !dispatch-event(Selkie::Event $ev) {
    return if $ev.input-type == NCTYPE_RELEASE;

    if $ev.event-type ~~ ResizeEvent {
        self!check-terminal-resize;
        return;
    }

    my $top = self!active-modal;
    if $top.defined {
        if $!focused.defined {
            my $widget = $!focused;
            while $widget.defined && $widget !=== $top {
                if $widget.handle-event($ev) {
                    return;
                }
                $widget = $widget.parent;
            }
        }
        return if $top.handle-event($ev);
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
    re-sync. Called from C<!maybe-check-terminal-resize> when our
    SIGWINCH tap (installed in TWEAK) signals a pending resize. Also
    called synchronously by C<!dispatch-event> when a C<ResizeEvent>
    arrives through the input queue (legacy path; with
    C<NCOPTION_NO_WINCH_SIGHANDLER> set, notcurses no longer emits
    these — but the path is harmless to keep as a defensive backstop).

    Calls C<notcurses_refresh> at the top to force notcurses to
    re-query terminal dimensions via TIOCGWINSZ. Without this we'd
    own the SIGWINCH handler but never tell notcurses about the new
    size — its stdplane stays at the old dim and nothing reflows.
    The refresh also re-emits every cell at the (possibly new)
    dimensions; the trailing refresh after render does the same job
    against the freshly composited frame to nail down terminal
    state. Two refreshes per resize event is acceptable for a
    one-time signal-driven flow.

    Returns True if dims actually changed. )
method !check-terminal-resize(--> Bool) {
    my uint32 $r = 0;
    my uint32 $c = 0;
    notcurses_refresh($!nc, $r, $c);
    return False if $r == $!rows && $c == $!cols;

    $!rows = $r;
    $!cols = $c;

    # Propagate dims synchronously through all screens (including
    # inactive ones — they'd otherwise render at stale dims when
    # switched to later) and through every modal in the stack — even
    # the ones not currently on top, because they'll need correct dims
    # when revealed by a close-modal. handle-resize cascades through
    # containers so leaf widgets know their new dims before any render.
    $!screen-manager.handle-resize($!rows, $!cols);
    .handle-resize($!rows, $!cols) for @!modal-stack;
    $!toast.handle-resize($!rows, $!cols) if $!toast;

    # Mark-dirty cascade — handle-resize short-circuits on unchanged
    # dims, so we force everyone to re-render even if their
    # allocation happened to match.
    self!mark-all-dirty(self.root) if self.root;
    self!mark-all-dirty($_)        for @!modal-stack;

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

    # Fire app-level resize callbacks AFTER the post-resize frame is
    # on screen. Cantina (and any consumer) uses this to park bitmap
    # sprixels — the parked planes get rebuilt at the new geometry on
    # the very next render tick, which the main loop will run as soon
    # as anything is dirty.
    .($!rows, $!cols) for @!resize-callbacks;
    True;
}

#|( Flag-gated wrapper around C<!check-terminal-resize>. Called from
    the main loop every frame; runs the underlying check only when our
    SIGWINCH tap has marked C<$!resize-pending>. The CAS clears the
    flag atomically before the check runs, so if a second SIGWINCH
    fires mid-check the flag will be set again and re-trigger on the
    next loop iteration. Returns True when a dim change was actually
    detected and the UI re-flowed; False otherwise. Used by the idle
    ladder to treat a resize as activity. )
method !maybe-check-terminal-resize(--> Bool) {
    return False unless cas($!resize-pending, 1, 0) == 1;
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
    # Only the topmost modal renders — modals are opaque overlays so the
    # ones beneath are fully covered. Subscriptions still dirty hidden
    # modals (e.g. the editor sitting under a confirm dialog), but those
    # dirty marks are paid out when close-modal pops the top and calls
    # mark-all-dirty on the now-revealed modal.
    my $top = self!active-modal;
    if $top.defined && $top.is-dirty {
        $top.render;
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
    # Close the SIGWINCH tap before tearing down notcurses — if a
    # signal arrives after notcurses_stop but before the tap is
    # closed, the handler would set a flag on a half-destroyed App.
    # The .? guards repeat shutdown calls; tap exposes no idempotent
    # close.
    $!resize-tap.?close;
    $!resize-tap = Nil;

    # Tear down every modal in the stack, deepest-on-top first (so each
    # destroy sees a sane stack). Pop emptied so a re-entrant shutdown
    # is a no-op rather than a double-destroy.
    while @!modal-stack {
        my $m = @!modal-stack.pop;
        @!pre-modal-focus-stack.pop;
        $m.destroy if $m.defined;
    }
    $!screen-manager.destroy;
    if $!nc {
        notcurses_stop($!nc);
        $!nc = NotcursesHandle;
    }
    # Stderr goes last so any diagnostics notcurses_stop emits still
    # land in the log file rather than the cleared terminal.
    self!uninstall-error-log;
}

method DESTROY() {
    self.shutdown if $!nc;
}

# --- Error-log redirection ------------------------------------------------

# POSIX fd shims for stderr redirection. dup(2) lets us save the
# original stderr fd before dup2'ing our log file onto fd 2; close(2)
# reaps the saved copy on shutdown. Declared here rather than at file
# scope so they stay private to the App's implementation.
sub c-dup(int32)           returns int32 is native is symbol('dup')   { * }
sub c-dup2(int32, int32)   returns int32 is native is symbol('dup2')  { * }
sub c-close(int32)         returns int32 is native is symbol('close') { * }

#|( Swap the active error-log file at runtime. Tears down the current
    redirection (restoring fd 2 to the original stderr), updates the
    path, and reinstalls the redirect pointing at the new file. Passing
    C<Str> (the type object) or an empty string disables redirection
    — fd 2 goes back to wherever it pointed before
    the first C<install-error-log>.

    Useful for apps whose log location only becomes known after some
    runtime event. App::Cantina is the canonical consumer: the path is
    C<{cantina-home}/{db-name}/error.log>, and C<db-name> is only
    known after the user selects / creates a profile on the login
    screen. The app boots with C<error-log> unset, then calls
    C<set-error-log> from its post-login handler.

    A new session banner is written to the new log file on each
    invocation so interleaved runs stay navigable. No-op (save for the
    banner) when called with the same path it already has. )
method set-error-log(Str $path) {
    self!uninstall-error-log;
    $!error-log = $path;
    self!install-error-log if $path.defined && $path.trim.chars > 0;
}

method !install-error-log() {
    # Defensive: if the caller passed whitespace-only, treat as unset.
    return unless $!error-log.defined && $!error-log.trim.chars > 0;

    # Auto-create the containing directory so the caller can pass
    # e.g. `~/.cairn/logs/error.log` without having to mkdir first.
    my $parent = $!error-log.IO.parent;
    try $parent.mkdir unless $parent.e;

    my $handle = try open $!error-log, :a;
    return unless $handle;
    $!error-log-handle = $handle;

    # Banner at the top of each session so the log file is navigable
    # across multiple runs. Uses native-descriptor so we don't rely on
    # Raku-level buffering interleaving correctly with the incoming
    # stderr stream post-dup2.
    my $banner = "=== session {DateTime.now.truncated-to('second')} ===\n";
    try $handle.print($banner);
    try $handle.flush;

    # Duplicate fd 2 so we can restore it on shutdown, then re-point
    # fd 2 at our log. After dup2, EVERY write to fd 2 (Raku $*ERR,
    # C library fprintf(stderr), notcurses diagnostics, panicking
    # runtime messages) lands in the log file.
    my $log-fd = $handle.native-descriptor;
    return unless $log-fd.defined && $log-fd >= 0;

    my $saved = c-dup(2);
    if $saved < 0 {
        $handle.close;
        $!error-log-handle = Nil;
        return;
    }
    $!saved-stderr-fd = $saved;

    my $rc = c-dup2($log-fd, 2);
    if $rc < 0 {
        # dup2 failed — undo the save and fall back to untouched stderr.
        c-close($saved);
        $!saved-stderr-fd = Int;
        $handle.close;
        $!error-log-handle = Nil;
    }
}

method !uninstall-error-log() {
    # Order matters: restore fd 2 first so any closing output during
    # the rest of shutdown still hits the log (which, at this point,
    # IS the fd 2 stream — writes to it just go to the original
    # stderr once restored).
    if $!saved-stderr-fd.defined && $!saved-stderr-fd >= 0 {
        c-dup2($!saved-stderr-fd, 2);
        c-close($!saved-stderr-fd);
        $!saved-stderr-fd = Int;
    }
    if $!error-log-handle {
        try $!error-log-handle.close;
        $!error-log-handle = Nil;
    }
}
