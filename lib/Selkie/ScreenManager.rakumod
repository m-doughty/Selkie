=begin pod

=head1 NAME

Selkie::ScreenManager - Named multi-screen management

=head1 SYNOPSIS

You rarely use C<ScreenManager> directly — L<Selkie::App>'s C<add-screen>,
C<switch-screen>, and C<screen-manager> methods forward to it. When you
do need the underlying object (e.g. to enumerate screen names):

=begin code :lang<raku>

my $sm = $app.screen-manager;

say $sm.active-screen;           # 'main'
say $sm.screen-names;            # ('login', 'main', 'settings')

# Route a keybind based on the active screen
$app.on-key('ctrl+n', -> $ {
    given $app.screen-manager.active-screen {
        when 'tasks' { create-task }
        when 'notes' { create-note }
    }
});

=end code

=head1 DESCRIPTION

A tiny registry mapping screen names to root containers, with one marked
as active at a time. C<Selkie::App> uses it to park inactive screens
off-screen while preserving their state.

Switching screens is fast — the inactive roots remain fully built, just
repositioned off-screen. Their widgets keep their state (text input
buffers, scroll positions, cursor positions) until the screen is
reactivated.

=head1 EXAMPLES

=head2 Checking before registering

=begin code :lang<raku>

unless $app.screen-manager.has-screen('settings') {
    $app.add-screen('settings', build-settings-screen());
}

=end code

=head2 Cleanup

Remove a screen you no longer need (e.g. after logout). Attempting to
remove the active screen throws:

=begin code :lang<raku>

$app.switch-screen('login');
$app.screen-manager.remove-screen('main');

=end code

=head1 SEE ALSO

=item L<Selkie::App> — wraps C<ScreenManager> with higher-level conveniences

=end pod

unit class Selkie::ScreenManager;

use Selkie::Widget;
use Selkie::Container;

has %!screens;
has Str $!active-name;

#|( Register a screen under a name. If this is the first screen added,
    it automatically becomes active. Subsequent screens join the registry
    but the active screen is unchanged. Idempotent by name: re-adding
    the same name overwrites the previous root. )
method add-screen(Str:D $name, Selkie::Container $root) {
    %!screens{$name} = $root;
    $!active-name = $name without $!active-name;
}

#|( Remove a registered screen by name. Fails if the screen is currently
    active — switch to another screen first. Destroys the screen's root
    widget tree. )
method remove-screen(Str:D $name) {
    fail "Cannot remove active screen" if $name eq ($!active-name // '');
    fail "Screen '$name' does not exist" unless %!screens{$name}:exists;
    %!screens{$name}.destroy;
    %!screens{$name}:delete;
}

#|( Make the named screen active. Marks its root dirty so it re-renders.
    Fails if no screen with that name exists. )
method switch-to(Str:D $name) {
    fail "Screen '$name' does not exist" unless %!screens{$name}:exists;
    return if $name eq ($!active-name // '');
    $!active-name = $name;
    self.active-root.mark-dirty;
}

#| The name of the currently active screen, or C<Nil> if no screens are
#| registered.
method active-screen(--> Str) { $!active-name }

#| The root container of the currently active screen, or the type object
#| C<Selkie::Container> if no screen is active.
method active-root(--> Selkie::Container) {
    return Selkie::Container without $!active-name;
    %!screens{$!active-name};
}

#| Sorted list of registered screen names.
method screen-names(--> List) { %!screens.keys.sort.List }

#| True if a screen with the given name is registered.
method has-screen(Str:D $name --> Bool) { %!screens{$name}:exists }

#| Focusable descendants of the active screen's root. Used by
#| C<Selkie::App> to build the Tab cycle.
method focusable-descendants(--> Seq) {
    my $root = self.active-root;
    return ().Seq without $root;
    $root.focusable-descendants;
}

#|( Propagate a terminal resize to every registered screen, not just
    the active one. Without this, switching to an inactive screen
    after a resize would render at stale dimensions until a re-layout
    happens to fire. Each screen's root is a Container, so its
    handle-resize cascades through its subtree synchronously. )
method handle-resize(UInt $rows, UInt $cols) {
    for %!screens.values -> $root {
        $root.handle-resize($rows, $cols);
    }
}

#| Destroy every registered screen and clear the active screen reference.
#| Called automatically by C<Selkie::App.shutdown>.
method destroy() {
    .destroy for %!screens.values;
    %!screens = ();
    $!active-name = Str;
}
