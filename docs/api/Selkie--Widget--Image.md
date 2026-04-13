NAME
====

Selkie::Widget::Image - Display an image via notcurses visual system

SYNOPSIS
========

```raku
use Selkie::Widget::Image;
use Selkie::Sizing;

my $img = Selkie::Widget::Image.new(
    file   => 'avatar.png',
    sizing => Sizing.fixed(20),
);

# Change later
$img.set-file('new-avatar.png');
$img.clear-image;
```

DESCRIPTION
===========

Loads and renders an image file onto its plane. If the terminal supports pixel graphics (Kitty, iTerm2, WezTerm, Ghostty, a few others), full-resolution pixels are rendered. Otherwise notcurses falls back to Unicode block / quadrant / braille art.

The image is centred in the widget's area and scaled to fit.

Pixel bleed
-----------

**Notcurses child planes are not clipped to parent bounds.** Pixel images can spill past the widget's logical rectangle into neighbouring cells. The usual workaround is to wrap the image in [Selkie::Widget::Border](Selkie--Widget--Border.md), which redraws its edges after content to cover bleed.

EXAMPLES
========

Preview in a Split
------------------

```raku
my $preview = Selkie::Widget::Image.new(sizing => Sizing.flex);
my $border  = Selkie::Widget::Border.new(title => 'Preview', sizing => Sizing.flex);
$border.set-content($preview);

# When user selects a new file:
$preview.set-file($selected-path);
```

SEE ALSO
========

  * [Selkie::Widget::Border](Selkie--Widget--Border.md) — wrap to contain pixel bleed

### method logical-height

```raku
method logical-height() returns UInt
```

Height in rows. Same as `self.rows`; provided for the ScrollView contract.

### method file

```raku
method file() returns Str
```

The currently displayed file path, or `Nil`.

### method set-file

```raku
method set-file(
    Str $path
) returns Mu
```

Swap the displayed image. No-op if the same path is already loaded. Triggers a re-blit on the next render.

### method clear-image

```raku
method clear-image() returns Mu
```

Unload the current image and clear the widget.

