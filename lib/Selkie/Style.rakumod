=begin pod

=head1 NAME

Selkie::Style - Text styling (colors + bold/italic/underline/strikethrough)

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Style;

# Bright cyan bold text
my $s1 = Selkie::Style.new(fg => 0x7AA2F7, bold => True);

# White on dark background, italic
my $s2 = Selkie::Style.new(fg => 0xFFFFFF, bg => 0x1A1A2E, italic => True);

# Apply to a widget
my $text = Selkie::Widget::Text.new(
    text   => 'hello',
    style  => $s1,
    sizing => Sizing.fixed(1),
);

=end code

=head1 DESCRIPTION

C<Selkie::Style> represents the visual attributes of rendered text:
foreground color, background color, and a set of text-style flags (bold,
italic, underline, strikethrough). Colors are 24-bit RGB integers in the
form C<0xRRGGBB>.

Widgets apply styles to their planes via C<self.apply-style($style)> in
their C<render> method. The framework provides sensible defaults through
L<Selkie::Theme> — you usually get a style from the theme rather than
constructing one directly.

=head1 EXAMPLES

=head2 Using theme-provided styles

Most widgets should pull styles from the theme so the app's palette
stays consistent:

=begin code :lang<raku>

method render() {
    return without self.plane;
    self.apply-style(self.theme.text);            # default text
    ncplane_putstr_yx(self.plane, 0, 0, 'normal');

    self.apply-style(self.theme.text-highlight);  # emphasised
    ncplane_putstr_yx(self.plane, 1, 0, 'selected');

    self.clear-dirty;
}

=end code

=head2 Overlaying an override on a theme style

Combine a base theme style with widget-local tweaks via C<merge>:

=begin code :lang<raku>

my $base = self.theme.text;
my $warning-variant = $base.merge(Selkie::Style.new(fg => 0xFF5555, bold => True));
self.apply-style($warning-variant);

=end code

C<merge> takes the non-null values of the override, falling back to the
base for anything the override doesn't set. Bold/italic/underline/strike
are logical-OR — if either side has the flag, the result has it.

=head1 SEE ALSO

=item L<Selkie::Theme> — collects named styles into a palette
=item L<Selkie::Widget> — every widget's C<apply-style> method takes one of these

=end pod

unit class Selkie::Style;

use Notcurses::Native::Types;

#| Foreground color as a 24-bit RGB integer (C<0xRRGGBB>). Leave undefined
#| to inherit from the surrounding context.
has UInt $.fg;

#| Background color as a 24-bit RGB integer (C<0xRRGGBB>). Leave undefined
#| to inherit.
has UInt $.bg;

#| Render text in bold.
has Bool $.bold = False;

#| Render text in italic.
has Bool $.italic = False;

#| Render text underlined.
has Bool $.underline = False;

#| Render text with strikethrough.
has Bool $.strikethrough = False;

#|( Return the notcurses style bitmask for the set of boolean flags
    enabled on this style. Widgets use this internally via
    C<apply-style>; you don't normally need to call it. )
method styles(--> UInt) {
    my UInt $s = 0;
    $s +|= NCSTYLE_BOLD      if $!bold;
    $s +|= NCSTYLE_ITALIC    if $!italic;
    $s +|= NCSTYLE_UNDERLINE if $!underline;
    $s +|= NCSTYLE_STRUCK    if $!strikethrough;
    $s;
}

#|( Combine this style with an override, producing a new style. Any
    color on the override takes precedence; any flag set on either
    side is set on the result (logical OR). Useful for producing
    variants of a theme style without replacing the whole thing. )
method merge(Selkie::Style $override --> Selkie::Style) {
    Selkie::Style.new(
        fg            => $override.fg            // $!fg,
        bg            => $override.bg            // $!bg,
        bold          => $override.bold          || $!bold,
        italic        => $override.italic        || $!italic,
        underline     => $override.underline     || $!underline,
        strikethrough => $override.strikethrough || $!strikethrough,
    );
}
