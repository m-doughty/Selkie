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

Every slot is a C<Selkie::Style>. The base UI slots are C<is required>
— a theme must explicitly define every one. Chart slots have
backward-compatible defaults derived from the base UI slots, so themes
predating the chart widgets keep working without modification.

=head2 Required (UI core)

=item C<base> — default background plus text color
=item C<text>, C<text-dim>, C<text-highlight> — normal, subdued, and emphasised text
=item C<border>, C<border-focused> — borders when unfocused vs containing the focused widget
=item C<input>, C<input-focused>, C<input-placeholder> — text input states
=item C<scrollbar-track>, C<scrollbar-thumb> — vertical scrollbar
=item C<divider> — the split bar in C<Selkie::Layout::Split>
=item C<tab-active>, C<tab-inactive> — active and inactive tabs in C<Selkie::Widget::TabBar>

=head2 Chart slots (defaulted, override for chart-rich apps)

Used by C<Selkie::Widget::Axis>, C<Selkie::Widget::Legend>, and the
chart family (C<Sparkline>, C<Plot>, C<BarChart>, C<Histogram>,
C<Heatmap>, C<ScatterPlot>, C<LineChart>). Defaults derive from the
required slots so existing themes work as-is; override these for a
distinct chart palette.

=item C<graph-axis> — axis line and tick marks (default: C<text-dim>)
=item C<graph-axis-label> — tick labels (default: C<text-dim>)
=item C<graph-grid> — optional gridlines behind chart bodies (default: C<divider>)
=item C<graph-line> — single-series line/sparkline color (default: C<border-focused>)
=item C<graph-fill> — fill-below color in line charts (default: C<border-focused>; consider a darker shade)
=item C<graph-legend-bg> — legend pane background (default: same bg as C<base>)

Multi-series colors are I<not> theme slots — see L<Selkie::Plot::Palette>
for the colorblind-safe series palettes (C<okabe-ito>, C<tol-bright>,
C<tableau-10>) and color ramps (C<viridis>, C<magma>, C<plasma>,
C<coolwarm>, C<grayscale>) used by chart widgets.

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

#| Active tab in C<Selkie::Widget::TabBar>. Distinct background so the
#| selected tab is unambiguously different from the rest — bracket
#| decorators alone aren't enough contrast at a glance.
has Selkie::Style $.tab-active is required;

#| Inactive tabs in C<Selkie::Widget::TabBar>.
has Selkie::Style $.tab-inactive is required;

#|( Axis line and tick-mark style for chart widgets. Defaults to
    C<text-dim> so existing themes inherit a reasonable look without
    needing to define this slot. Override for a distinct chart axis
    color. )
has Selkie::Style $.graph-axis = $!text-dim;

#|( Tick label style for chart axes. Defaults to C<text-dim>. )
has Selkie::Style $.graph-axis-label = $!text-dim;

#|( Optional gridline style for chart bodies (used by C<LineChart> and
    C<ScatterPlot> when grids are enabled). Defaults to C<divider>. )
has Selkie::Style $.graph-grid = $!divider;

#|( Default series color for single-series chart widgets
    (C<Sparkline>, single-series C<LineChart>). Multi-series widgets
    pull colors from C<Selkie::Plot::Palette> instead of this slot.
    Defaults to C<border-focused>. )
has Selkie::Style $.graph-line = $!border-focused;

#|( Fill-below color for C<LineChart> when fill is enabled. Defaults
    to C<border-focused>; for visual depth set this to a darker shade
    of C<graph-line>. )
has Selkie::Style $.graph-fill = $!border-focused;

#|( Background style for C<Selkie::Widget::Legend>. Defaults to a
    style with the same background as C<base>, so legends blend by
    default. Override with a contrasting bg for a distinct legend
    pane. )
has Selkie::Style $.graph-legend-bg = Selkie::Style.new(bg => $!base.bg);

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
        tab-active        => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x7AA2F7, bold => True),
        tab-inactive      => Selkie::Style.new(fg => 0x8080A0, bg => 0x1A1A2E),
        graph-axis        => Selkie::Style.new(fg => 0x808098),
        graph-axis-label  => Selkie::Style.new(fg => 0x8080A0),
        graph-grid        => Selkie::Style.new(fg => 0x2A2A4A),
        graph-line        => Selkie::Style.new(fg => 0x7AA2F7),
        graph-fill        => Selkie::Style.new(fg => 0x3A4A8A),
        graph-legend-bg   => Selkie::Style.new(bg => 0x24243E),
    );
}
