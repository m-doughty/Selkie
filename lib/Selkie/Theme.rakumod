=begin pod

=head1 NAME

Selkie::Theme - Named palette of C<Selkie::Style> slots

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Style;
use Selkie::Theme;

# Build a custom theme
my $theme = Selkie::Theme.new(
    base              => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x000000),
    text              => Selkie::Style.new(fg => 0xEEEEEE),
    text-dim          => Selkie::Style.new(fg => 0x888888),
    text-highlight    => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
    border            => Selkie::Style.new(fg => 0x444444),
    border-focused    => Selkie::Style.new(fg => 0x00FF00, bold => True),
    input             => Selkie::Style.new(fg => 0xEEEEEE, bg => 0x111111),
    input-focused     => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x222222),
    input-placeholder => Selkie::Style.new(fg => 0x666666, italic => True),
    scrollbar-track   => Selkie::Style.new(fg => 0x333333),
    scrollbar-thumb   => Selkie::Style.new(fg => 0x00FF00),
    divider           => Selkie::Style.new(fg => 0x444444),
);

# Use it app-wide
my $app = Selkie::App.new(:$theme);

=end code

=head1 DESCRIPTION

A theme is a collection of named C<Selkie::Style> slots — one per visual
role in the framework. Widgets look up slots by name
(C<self.theme.border>, C<self.theme.text-highlight>, etc.) so you can
restyle the whole app by providing a different theme.

Themes are inherited through the widget tree: a widget's effective theme
is its own explicit theme (if set), otherwise its parent's, falling back
to C<Selkie::Theme.default>.

=head1 EXAMPLES

=head2 Default theme

If you don't pass one to C<Selkie::App>, the built-in dark palette is used:

=begin code :lang<raku>

my $app = Selkie::App.new;   # uses Selkie::Theme.default

=end code

=head2 Scoping a different theme to a subtree

Give a specific panel a different palette without affecting the rest of
the app:

=begin code :lang<raku>

my $warning-theme = Selkie::Theme.default;
# (imagine we mutated this or built a fresh one with red borders)
$warning-panel.set-theme($warning-theme);

=end code

=head2 Runtime theme swap

Subscribe a root container to a store path that holds the current theme,
and swap at will:

=begin code :lang<raku>

$store.register-handler('theme/toggle', -> $st, % {
    my $dark = $st.get-in('dark') // True;
    (db => { dark => !$dark },);
});

$store.subscribe-with-callback(
    'theme',
    -> $s { $s.get-in('dark') // True },
    -> Bool $dark { $root.set-theme($dark ?? dark-theme() !! light-theme()) },
    $root,
);

=end code

=head1 SLOTS

Every slot is a C<Selkie::Style>. All slots are C<is required> — a theme
must explicitly define every one.

=item C<base> — default background plus text color
=item C<text>, C<text-dim>, C<text-highlight> — normal, subdued, and emphasised text
=item C<border>, C<border-focused> — borders when unfocused vs containing the focused widget
=item C<input>, C<input-focused>, C<input-placeholder> — text input states
=item C<scrollbar-track>, C<scrollbar-thumb> — vertical scrollbar
=item C<divider> — the split bar in C<Selkie::Layout::Split>

=head2 Custom slots

Extend a theme with project-specific slots via the C<%.custom> hash.
Widgets can look them up via C<self.theme.slot('my-slot-name')>:

=begin code :lang<raku>

my $theme = Selkie::Theme.new(
    ...,
    custom => {
        'chat-bot'  => Selkie::Style.new(fg => 0x9ECE6A),
        'chat-user' => Selkie::Style.new(fg => 0x7AA2F7),
    },
);

# In a custom widget:
self.apply-style(self.theme.slot('chat-bot'));

=end code

C<slot> falls back to the C<base> style if the name isn't registered.

=end pod

unit class Selkie::Theme;

use Selkie::Style;

#| The base background and default text color for the theme.
has Selkie::Style $.base is required;

#| Border style for unfocused borders.
has Selkie::Style $.border is required;

#| Border style for borders whose descendant has focus. Auto-applied by
#| C<Selkie::Widget::Border> based on store focus state.
has Selkie::Style $.border-focused is required;

#| Default text style.
has Selkie::Style $.text is required;

#| Subdued text — for captions, help text, placeholder-ish content.
has Selkie::Style $.text-dim is required;

#| Emphasised text — selected list items, highlighted values.
has Selkie::Style $.text-highlight is required;

#| Text input style when unfocused.
has Selkie::Style $.input is required;

#| Text input style when focused.
has Selkie::Style $.input-focused is required;

#| Placeholder text style (shown when an input is empty and unfocused).
has Selkie::Style $.input-placeholder is required;

#| Scrollbar track (the background rail).
has Selkie::Style $.scrollbar-track is required;

#| Scrollbar thumb (the filled bar showing position).
has Selkie::Style $.scrollbar-thumb is required;

#| Divider line in C<Selkie::Layout::Split>.
has Selkie::Style $.divider is required;

#|( Extra application-specific slots. Keyed by name, values are
    C<Selkie::Style>. Look them up via C<slot(name)>. )
has Selkie::Style %.custom;

#|( Fetch a named custom slot, falling back to C<base> if the name
    isn't registered. Useful for app-specific categories of styling
    that don't fit the built-in slots. )
method slot(Str:D $name --> Selkie::Style) {
    %!custom{$name} // $!base;
}

#|( The built-in dark theme. Used automatically by C<Selkie::App> when
    no theme is provided. Browse the implementation for exact colors —
    it's a cool blue-grey palette with accent on 0x7AA2F7. )
method default(--> Selkie::Theme) {
    Selkie::Theme.new(
        base              => Selkie::Style.new(fg => 0xC0C0C0, bg => 0x1A1A2E),
        border            => Selkie::Style.new(fg => 0x4A4A6A, bg => 0x1A1A2E),
        border-focused    => Selkie::Style.new(fg => 0x7AA2F7, bg => 0x1A1A2E, bold => True),
        text              => Selkie::Style.new(fg => 0xC0C0C0),
        text-dim          => Selkie::Style.new(fg => 0x606080),
        text-highlight    => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
        input             => Selkie::Style.new(fg => 0xC0C0C0, bg => 0x24243E),
        input-focused     => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x2A2A4A),
        input-placeholder => Selkie::Style.new(fg => 0x606080, bg => 0x24243E, italic => True),
        scrollbar-track   => Selkie::Style.new(fg => 0x2A2A4A, bg => 0x1A1A2E),
        scrollbar-thumb   => Selkie::Style.new(fg => 0x7AA2F7, bg => 0x1A1A2E),
        divider           => Selkie::Style.new(fg => 0x3A3A5A, bg => 0x1A1A2E),
    );
}
