unit class Selkie::App;

use NativeCall;

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Input;

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
has Selkie::Theme $.theme;
has Selkie::Store $.store = Selkie::Store.new;
has Selkie::ScreenManager $!screen-manager = Selkie::ScreenManager.new;
has Selkie::Widget::Modal $!active-modal;
has Selkie::Widget::Toast $!toast;
has Selkie::Widget $!focused;
has Selkie::Widget $!pre-modal-focus;  # saved focus when modal opens
has @!global-keybinds;
has @!frame-callbacks;
has Bool $!running = False;
has UInt $!rows = 0;
has UInt $!cols = 0;
has Supplier $!event-supplier = Supplier.new;

method screen-manager(--> Selkie::ScreenManager) { $!screen-manager }
method focused(--> Selkie::Widget) { $!focused }
method event-supply(--> Supply) { $!event-supplier.Supply }

# Convenience: returns the active screen's root container.
# For single-screen apps, add-screen('main', ...) then use .root
method root(--> Selkie::Container) { $!screen-manager.active-root }

submethod TWEAK() {
    $!theme //= Selkie::Theme.default;

    my $opts = NotcursesOptions.new(
        flags => NCOPTION_SUPPRESS_BANNERS,
    );
    $!nc = notcurses_init($opts, Pointer);
    die "Failed to initialize notcurses" without $!nc;

    notcurses_mice_enable($!nc, NCMICE_BUTTON_EVENT +| NCMICE_DRAG_EVENT);

    $!stdplane = notcurses_stdplane($!nc);
    my uint32 $r = 0;
    my uint32 $c = 0;
    notcurses_stddim_yx($!nc, $r, $c);
    $!rows = $r;
    $!cols = $c;

    # Drain any pending terminal responses (color queries, etc.)
    # that arrive shortly after notcurses init
    my $drain-timeout = Timespec.new(tv_sec => 0, tv_nsec => 50_000_000);  # 50ms
    loop {
        my $ni = Ncinput.new;
        my $id = notcurses_get($!nc, $drain-timeout, $ni);
        last if $id == 0;  # no more pending input
    }

    # Register default focus handlers
    self!register-focus-handlers;

    # Safety net: if anything between App.new and the end of the program
    # throws (e.g. setup code, app/init handlers, anything before $app.run),
    # the CATCH inside .run never gets a chance to restore the terminal.
    # Register an END phaser to guarantee cleanup. shutdown is idempotent —
    # it no-ops if notcurses is already stopped.
    my $self = self;
    END { $self.shutdown if $self.defined }
}

method !register-focus-handlers() {
    # Focus event: set the focused widget
    $!store.register-handler('ui/focus', -> $store, %ev {
        (db => { ui => { focused-widget => %ev<widget> } },);
    });

    # Focus cycling
    $!store.register-handler('ui/focus-next', -> $store, %ev {
        # Handled imperatively since it needs widget tree access
        # The handler just sets a flag; App processes it
        (db => { ui => { focus-action => 'next' } },);
    });

    $!store.register-handler('ui/focus-prev', -> $store, %ev {
        (db => { ui => { focus-action => 'prev' } },);
    });

    # Default keybinds
    self.on-key: 'tab', -> $ { $!store.dispatch('ui/focus-next') };
    self.on-key: 'shift+tab', -> $ { $!store.dispatch('ui/focus-prev') };
    self.on-key: 'esc', -> $ { self.close-modal if self.has-modal };
    self.on-key: 'ctrl+q', -> $ { self.quit };
}

# --- Screen management ---

method add-screen(Str:D $name, Selkie::Container $root) {
    $root.set-theme($!theme);
    $root.set-store($!store);
    $root.init-plane($!stdplane, y => 0, x => 0, rows => $!rows, cols => $!cols);
    $root.set-viewport(abs-y => 0, abs-x => 0, rows => $!rows, cols => $!cols);
    # Hide non-first screens offscreen
    if $!screen-manager.screen-names.elems > 0 {
        $root.reposition($!rows, 0);
    }
    $!screen-manager.add-screen($name, $root);
}

method switch-screen(Str:D $name) {
    my $old-root = self.root;
    $!screen-manager.switch-to($name);
    my $new-root = self.root;
    # Hide old screen offscreen, show new screen at origin
    $old-root.reposition($!rows, 0) if $old-root && $old-root !=== $new-root;
    if $new-root {
        $new-root.reposition(0, 0);
        $new-root.resize($!rows, $!cols);
        $new-root.mark-dirty;
    }
}

# --- Toast ---

method toast(Str:D $message, Num :$duration = 2e0) {
    without $!toast {
        $!toast = Selkie::Widget::Toast.new;
        $!toast.attach($!stdplane, rows => $!rows, cols => $!cols);
    }
    $!toast.resize-screen($!rows, $!cols);
    $!toast.show($message, :$duration);
}

# --- Modal support ---

method show-modal(Selkie::Widget::Modal $modal) {
    $!pre-modal-focus = $!focused;
    $!active-modal = $modal;
    $modal.set-theme($!theme);
    $modal.set-store($!store);
    $modal.init-plane($!stdplane, y => 0, x => 0, rows => $!rows, cols => $!cols);
    $modal.mark-dirty;

    # Auto-focus first focusable in modal
    my @fd = $modal.focusable-descendants.List;
    self.focus(@fd[0]) if @fd;
}

method close-modal() {
    return without $!active-modal;
    $!active-modal.destroy;
    $!active-modal = Selkie::Widget::Modal;
    # Restore pre-modal focus
    if $!pre-modal-focus.defined {
        self.focus($!pre-modal-focus);
        $!pre-modal-focus = Selkie::Widget;
    }
    # Mark every widget on the active screen dirty — the modal's planes
    # have been destroyed but the widgets behind it kept their own clean
    # state, so they need a forced re-render to repaint over the now-empty
    # area. mark-dirty alone only flags root, not its descendants.
    self!mark-all-dirty(self.root) if self.root;
}

method has-modal(--> Bool) { $!active-modal.defined }

# --- Keybinds ---

method on-key(Str:D $spec, &handler) {
    @!global-keybinds.push: Keybind.parse($spec, &handler);
}

method on-frame(&callback) {
    @!frame-callbacks.push(&callback);
}

# --- Focus management ---

method focus(Selkie::Widget $w) {
    $!focused.set-focused(False) if $!focused.defined && $!focused.can('set-focused');
    $!focused = $w;
    $w.set-focused(True) if $w.can('set-focused');
    # Update store (won't re-trigger since handler just sets same value)
    $!store.dispatch('ui/focus', widget => $w);
}

method focus-next() {
    self!do-focus-cycle(1);
}

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

method quit() {
    $!running = False;
}

method run() {
    $!running = True;
    self!render-frame;

    my $timeout = Timespec.new(tv_sec => 0, tv_nsec => 16_000_000);  # ~60fps
    while $!running {
        my $ni = Ncinput.new;
        my $id = notcurses_get($!nc, $timeout, $ni);
        if $id > 0 {
            my $ev = Selkie::Event.from-ncinput($ni);
            $!event-supplier.emit($ev);
            self!dispatch-event($ev);
        }
        .() for @!frame-callbacks;
        $!store.tick;
        self!process-focus-actions;
        $!toast.tick if $!toast;
        self!render-frame;
    }

    self.shutdown;

    CATCH {
        default {
            # Always restore terminal, even on unhandled exceptions
            self.shutdown;
            $*ERR.say("Selkie crashed: {.message}");
            $*ERR.say(.backtrace.full);
            exit 1;
        }
    }
}

method !dispatch-event(Selkie::Event $ev) {
    # Ignore key/mouse release events
    return if $ev.input-type == NCTYPE_RELEASE;

    # Handle resize
    if $ev.event-type ~~ ResizeEvent {
        my uint32 $r = 0;
        my uint32 $c = 0;
        notcurses_stddim_yx($!nc, $r, $c);
        $!rows = $r;
        $!cols = $c;
        my $root = self.root;
        if $root {
            $root.resize($!rows, $!cols);
            self!mark-all-dirty($root);
        }
        if $!active-modal {
            $!active-modal.resize($!rows, $!cols);
            self!mark-all-dirty($!active-modal);
        }
        return;
    }

    # Modal captures all events when active
    if $!active-modal {
        # Dispatch to focused widget (but don't bubble past the modal)
        if $!focused.defined {
            my $widget = $!focused;
            while $widget.defined && $widget !=== $!active-modal {
                if $widget.handle-event($ev) {
                    return;
                }
                $widget = $widget.parent;
            }
        }
        # Check modal's own keybinds (esc etc)
        return if $!active-modal.handle-event($ev);
        # Then global keybinds (tab for focus cycling)
        for @!global-keybinds -> $kb {
            if $kb.matches($ev) {
                $kb.handler.($ev);
                return;
            }
        }
        # Consume — modal is a focus trap
        return;
    }

    # Bubble: focused widget → parent → ... → root → global keybinds
    self!bubble-event($ev);
}

method !bubble-event(Selkie::Event $ev --> Bool) {
    # Start at focused widget, walk up the parent chain
    my $widget = $!focused;
    while $widget.defined {
        return True if $widget.handle-event($ev);
        $widget = $widget.parent;
    }

    # Nothing in the hierarchy consumed it — try global keybinds
    for @!global-keybinds -> $kb {
        if $kb.matches($ev) {
            $kb.handler.($ev);
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
    # Border content
    if $w.can('content') && $w.content.defined {
        self!mark-all-dirty($w.content);
    }
}

method !render-frame() {
    my $root = self.root;
    $root.render if $root && $root.is-dirty;
    $!active-modal.render if $!active-modal && $!active-modal.is-dirty;
    $!toast.render if $!toast && $!toast.is-visible;
    notcurses_render($!nc);
}

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
