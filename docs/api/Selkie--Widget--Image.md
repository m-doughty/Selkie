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

Sprixel position tracking
-------------------------

Notcurses pixel sprixels don't follow their parent plane when it moves — the sprixel stays painted at its old terminal coordinates until the blit-plane is explicitly destroyed. Image detects moves by asking notcurses for the plane's true absolute position each render (via `ncplane_abs_y` / `ncplane_abs_x`), not by trusting `Widget.abs-y` / `Widget.abs-x`. This means Image is immune to upstream containers that forget to propagate `set-viewport` to their descendants — the cache invalidates the moment notcurses reports a different position, regardless of whether any Selkie-level tracking was updated.

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

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Eagerly destroy the blit-plane on a real resize. The blit-plane is a child of `self.plane`, sized to the scaled image dimensions — when the parent shrinks (e.g. the host card is bottom-clipped by CardList), notcurses doesn't auto-clip or auto-destroy the child, so a stale sprixel can extend beyond the Image's new bounds and paint into whatever sits below. `render` would clean up the same blit-plane on its next cache miss, but tearing it down here makes the cleanup atomic with the resize itself, ruling out any window where the larger blit-plane lingers.

### method file

```raku
method file() returns Str
```

The currently displayed file path, or `Nil`.

### method blit-cache-valid

```raku
method blit-cache-valid() returns Bool
```

True when the blit-plane cache has an active, non-invalidated entry from a previous successful blit. Intended for tests that assert cache invalidation semantics without needing a live notcurses plane — callers shouldn't depend on this in production rendering logic (`render` handles cache decisions itself).

### method populate-blit-cache-for-test

```raku
method populate-blit-cache-for-test(
    Int :$rows! where { ... },
    Int :$cols! where { ... },
    Int :$abs-y = 0,
    Int :$abs-x = 0,
    Str :$file!
) returns Mu
```

Test-only hook: seed the cache with arbitrary values so tests can verify invalidation paths without running `render` (which needs a live notcurses plane). Production code populates these fields only from inside `render` on a successful blit.

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

### method park

```raku
method park() returns Mu
```

When an Image is parked off-screen by a container swap (e.g. tab switch in CharacterEditor), the parent plane moves but the sprixel — Sixel/Kitty pixel data the terminal renders at an absolute screen position — is NOT cleared by notcurses just because its plane moved. Destroy the blit-plane so the next notcurses_render flushes the sprixel removal to the terminal. The blit-plane gets recreated when render fires again on re-install.

