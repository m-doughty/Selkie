NAME
====

Selkie::Style - Text styling (colors + bold/italic/underline/strikethrough)

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

`Selkie::Style` represents the visual attributes of rendered text: foreground color, background color, and a set of text-style flags (bold, italic, underline, strikethrough). Colors are 24-bit RGB integers in the form `0xRRGGBB`.

Widgets apply styles to their planes via `self.apply-style($style)` in their `render` method. The framework provides sensible defaults through [Selkie::Theme](Selkie--Theme.md) — you usually get a style from the theme rather than constructing one directly.

EXAMPLES
========

Using theme-provided styles
---------------------------

Most widgets should pull styles from the theme so the app's palette stays consistent:

```raku
method render() {
    return without self.plane;
    self.apply-style(self.theme.text);            # default text
    ncplane_putstr_yx(self.plane, 0, 0, 'normal');

    self.apply-style(self.theme.text-highlight);  # emphasised
    ncplane_putstr_yx(self.plane, 1, 0, 'selected');

    self.clear-dirty;
}
```

Overlaying an override on a theme style
---------------------------------------

Combine a base theme style with widget-local tweaks via `merge`:

```raku
my $base = self.theme.text;
my $warning-variant = $base.merge(Selkie::Style.new(fg => 0xFF5555, bold => True));
self.apply-style($warning-variant);
```

`merge` takes the non-null values of the override, falling back to the base for anything the override doesn't set. Bold/italic/underline/strike are logical-OR — if either side has the flag, the result has it.

SEE ALSO
========

  * [Selkie::Theme](Selkie--Theme.md) — collects named styles into a palette

  * [Selkie::Widget](Selkie--Widget.md) — every widget's `apply-style` method takes one of these

### has UInt $.fg

Foreground color as a 24-bit RGB integer (`0xRRGGBB`). Leave undefined to inherit from the surrounding context.

### has UInt $.bg

Background color as a 24-bit RGB integer (`0xRRGGBB`). Leave undefined to inherit.

### has Bool $.bold

Render text in bold.

### has Bool $.italic

Render text in italic.

### has Bool $.underline

Render text underlined.

### has Bool $.strikethrough

Render text with strikethrough.

### method styles

```raku
method styles() returns UInt
```

Return the notcurses style bitmask for the set of boolean flags enabled on this style. Widgets use this internally via `apply-style`; you don't normally need to call it.

### method merge

```raku
method merge(
    Selkie::Style $override
) returns Selkie::Style
```

Combine this style with an override, producing a new style. Any color on the override takes precedence; any flag set on either side is set on the result (logical OR). Useful for producing variants of a theme style without replacing the whole thing.

