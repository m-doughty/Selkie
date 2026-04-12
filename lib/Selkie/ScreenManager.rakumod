unit class Selkie::ScreenManager;

use Selkie::Widget;
use Selkie::Container;

has %!screens;
has Str $!active-name;

method add-screen(Str:D $name, Selkie::Container $root) {
    %!screens{$name} = $root;
    $!active-name = $name without $!active-name;
}

method remove-screen(Str:D $name) {
    fail "Cannot remove active screen" if $name eq ($!active-name // '');
    fail "Screen '$name' does not exist" unless %!screens{$name}:exists;
    %!screens{$name}.destroy;
    %!screens{$name}:delete;
}

method switch-to(Str:D $name) {
    fail "Screen '$name' does not exist" unless %!screens{$name}:exists;
    return if $name eq ($!active-name // '');
    $!active-name = $name;
    self.active-root.mark-dirty;
}

method active-screen(--> Str) { $!active-name }

method active-root(--> Selkie::Container) {
    return Selkie::Container without $!active-name;
    %!screens{$!active-name};
}

method screen-names(--> List) { %!screens.keys.sort.List }

method has-screen(Str:D $name --> Bool) { %!screens{$name}:exists }

method focusable-descendants(--> Seq) {
    my $root = self.active-root;
    return ().Seq without $root;
    $root.focusable-descendants;
}

method destroy() {
    .destroy for %!screens.values;
    %!screens = ();
    $!active-name = Str;
}
