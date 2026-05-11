NAME
====

Selkie::Widget::Image - Display an image via notcurses pixel graphics

SYNOPSIS
========

```raku
use Selkie::Widget::Image;
use Selkie::Sizing;

my $img = Selkie::Widget::Image.new(
    file   => 'avatar.png',
    sizing => Sizing.fixed(20),
);

$img.set-file('new-avatar.png');
$img.clear-image;
```

DESCRIPTION
===========

Loads and renders an image file onto its plane. If the terminal supports pixel graphics — Sixel, Kitty graphics protocol, iTerm2 inline images (notcurses unifies all three behind `NCBLIT_PIXEL`) — full-resolution pixels are rendered. Otherwise notcurses falls back to Unicode block / quadrant / braille art.

Rendering model
---------------

`Image.render` is a pure function of three inputs:

  * Source file content (the PNG / JPEG path).

  * The Image's own plane's notcurses-tracked screen rectangle (live, queried each render via `ncplane_abs_y` / `ncplane_dim_yx`).

  * The chain of ancestor plane rectangles up to the terminal viewport (also queried via notcurses each render).

Every user-visible state change — a parent scrolling, a sibling card resizing the layout, a terminal zoom, a modal mounting — flows through Selkie's dirty-propagation framework (`set-viewport`, `handle-resize`, `Container.!render-children`) and triggers `Image.render` via the normal dirty-driven render walk.

The render does exactly one thing: if the Image's plane is fully contained in every ancestor's plane and within the terminal viewport, emit the sprixel. Otherwise, ensure no live blit exists and skip. There is no "park" position, no Widget-cache visibility check, no per-Image state machine — just a notcurses-driven bounds intersection.

Why notcurses, not Widget cache, for visibility decisions
---------------------------------------------------------

Selkie keeps two parallel position states for every widget: the Widget attributes (`$.abs-y`, `$.abs-x`, `$.rows`, `$.cols`) updated by parent layouts via `set-viewport` / `handle-resize`, and the notcurses plane position updated by `ncplane_move_yx` and notcurses's internal `move_bound_planes` cascade. For text widgets these stay in sync because cell ops are bounded by the plane and any divergence is invisible. For sprixels they catastrophically diverge — sprixel pixels paint at notcurses-tracked coordinates, and any cache desync produces blits at the wrong place.

So Image's visibility decision queries notcurses directly. Widget cache is fine for everything else.

Park
----

`park` destroys the blit-plane and does nothing else. `Container.park` in the ancestor chain handles moving planes off-screen via its reposition cascade; notcurses's `move_bound_planes` carries the Image's plane along with the ancestor moves. When the cascade later unparks (e.g., a card scrolls back into view), the dirty-driven render walk reaches Image, the visibility check sees the now-on-screen notcurses position, and a fresh blit is emitted.

Pixel bleed protection
----------------------

Notcurses doesn't clip child planes' pixels to ancestor bounds. The "fully contained in every ancestor" gate replaces any clipping — Image is hidden during partial overlap rather than emitting pixels that could bleed past an ancestor's edge. Partial-clip rendering (showing the visible portion only) is intentionally out of scope for this version; can be added later via Vips-based source cropping.

There's a second, protocol-specific source of bleed: Sixel emits pixels in 6-pixel-tall groups, so a sprixel always rounds UP to the next multiple of 6 vertical pixels on the wire. When the cell pixel height isn't a multiple of 6, that rounding paints a few pixels beyond the plane's pixel rectangle and into the next cell row. `!emit-blit` detects the active pixel implementation and shrinks the blit-plane vertically by at most one cell when the protocol has a > 1 vertical granularity, so the rounded-up pixel emit always fits inside Image's own plane. Kitty graphics protocol and iTerm2 inline images use exact pixel sizes (granularity 1); for those, no shrinkage applies.

EXAMPLES
========

Preview in a Split
------------------

```raku
my $preview = Selkie::Widget::Image.new(sizing => Sizing.flex);
my $border  = Selkie::Widget::Border.new(title => 'Preview', sizing => Sizing.flex);
$border.set-content($preview);

$preview.set-file($selected-path);
```

SEE ALSO
========

  * [Selkie::Widget::Border](Selkie--Widget--Border.md) — wrap to contain visual bleed of cell content

  * [Selkie::EffectiveBounds](Selkie--EffectiveBounds.md) — value class returned by the bounds intersection helper

### has Bool $.clip-only

When True, partial-clip rendering (`render-viewport-crop`, called by row-scrolling containers like `ViewportedCardList`) preserves the image's natural scale and on-screen position: the image is rendered as it would appear when fully visible, and rows / columns outside the visible viewport are simply not emitted. Defaults to False — the standard behaviour, where the visible cell rectangle is filled with a scaled-down crop of the source. Use this when you have a stack of images inside a row-scrolling list and want the picture to feel pinned to its host card rather than breathing in and out as the card slides past the viewport edge. The cost is that fully-clipped images (no visible cells overlap the natural image rectangle) produce no output — exactly the desired behaviour, but worth knowing.

### has Int $!last-abs-y

Cached state from the previous successful blit. Compared each render against the live notcurses values; when they diverge we tear down + re-blit. Cleared by `destroy-blit-plane`.

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

React to a parent layout's resize cascade by updating own dimensions and marking dirty. We always mark dirty even when our own dims didn't change — handle-resize fires from ancestor state changes that may affect our visibility chain even without changing our own size, and a redundant render that hits the unchanged cache is essentially free (one rect-intersection walk + one snapshot diff).

### method file

```raku
method file() returns Str
```

The currently displayed file path, or `Nil`.

### method has-blit-plane

```raku
method has-blit-plane() returns Bool
```

True when an active blit-plane currently exists.

### method set-file

```raku
method set-file(
    Str $path
) returns Mu
```

Swap the displayed image. No-op if the same path is already loaded. Triggers a re-blit on the next render via the dirty cascade.

### method clear-image

```raku
method clear-image() returns Mu
```

Unload the current image and clear the widget.

### method ensure-scaled-visual

```raku
method ensure-scaled-visual(
    $nc,
    Int $cell-px-y where { ... },
    Int $cell-px-x where { ... }
) returns Bool
```

For the clip-only render path: ensure `$!visual`'s pixel dimensions equal the natural rendering dims (the dims notcurses's NCSCALE_SCALE would produce when blitting the original source into the full widget cell rect). When this holds, NCSCALE_NONE blits source pixels 1:1 to dest pixels, so partial-clip renders are pixel-exact regardless of source-crop aspect — no NCSCALE_SCALE letterbox drift per scroll step. Returns True iff `$!visual` is now at natural dims and ready for NCSCALE_NONE blits. For the clip-only render path: pre-scale `$!visual` to its **cell-aligned** natural rendering dimensions — i.e. `rcelly × cell-px-y` tall by `rcellx × cell-px-x` wide. After this, every image cell row is exactly `cell-px-y` source pixels tall (and similarly for cols), so the per-frame source-crop math in `render-viewport-crop`'s clip-only branch is pure integer arithmetic with no rounding drift, and a source crop of N image cell rows is exactly N × cell-px-y source pixels — which matches the dest blit plane's pixel rect of N cells × cell-px-y. Returns True iff the visual is now at cell-aligned dims and ready for `NCSCALE_STRETCH` blits that render 1:1. The cache invalidates whenever the widget's natural cell footprint changes (terminal resize / widget cols/rows change), at which point we reload from the source file to avoid compounding interpolation loss from repeated re-scaling of an already-downscaled visual.

### method destroy-blit-plane

```raku
method destroy-blit-plane() returns Nil
```

Tear down the current blit-plane and clear the cached state. Sets the underlying notcurses sprixel to SPRIXEL_HIDE; the actual sprixel-remove escape goes out at the next end-of-frame notcurses_render, where rasterize_sprixels() processes every SPRIXEL_HIDE before any SPRIXEL_INVALIDATED in a single pass. So a destroy + create within the same frame produces the correct wire sequence — no mid-walk render needed. Idempotent: returns immediately if no live blit. Note the `without` test is on `$!blit-plane` directly, NOT `$!blit-plane.defined` — the latter returns a Bool which is always defined, so `without Bool` never fires the early-return. Subtle Raku gotcha.

### method park

```raku
method park() returns Mu
```

Park: destroy the blit-plane. Container.park's reposition cascade handles moving the plane off-screen — notcurses's move_bound_planes carries this Image's plane along with the ancestor moves. The next dirty-driven render reaches us via the cascade, the visibility chain sees the off-screen notcurses position, and the emit is skipped. When ancestors unpark (e.g., a card scrolls back into view), the dirty cascade fires again, the visibility check sees the on-screen notcurses position, and a fresh blit emits.

### method destroy

```raku
method destroy() returns Mu
```

Tear down the sprixel and the underlying ncvisual / blit plane, then destroy the widget's own plane. Always called on app shutdown or when the widget is explicitly removed; sprixel cleanup is critical because notcurses won't auto-evict pixels left on the terminal when their carrier plane goes away.

### method render

```raku
method render() returns Mu
```

Per-frame render. When the source file is unset / unloadable, paints a fallback message in dim text. When occluded by a modal or off the visible region, ensures any prior sprixel is torn down before returning. The blit plane is created lazily on the first render that actually emits pixels.

### method render-viewport-crop

```raku
method render-viewport-crop(
    Notcurses::Native::Types::NcplaneHandle :$parent-plane!,
    Int :$dest-y!,
    Int :$dest-x!,
    Int :$source-row!,
    Int :$source-col = 0,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Bool
```

Internal hook for row-viewport containers that render children into an offscreen logical plane and then composite only a visible cell slice. Normal Image.render intentionally hides partially clipped sprixels to prevent bleed; this hook performs an explicit source crop and blits the visible rectangle directly into the caller's viewport plane.

### method emit-blit

```raku
method emit-blit() returns Nil
```

Create a fresh blit-plane sized to the Image's full plane area at offset (0, 0) and blit the loaded visual into it. Called from render() only when the visibility check passed (Image is fully contained in every ancestor) — so we know we can emit the entire image without bleeding past anything.

### sub effective-screen-rect-for

```raku
sub effective-screen-rect-for(
    Selkie::Widget $w
) returns Selkie::EffectiveBounds
```

Walk the widget's parent chain via notcurses queries (NOT Widget cache) and return the rectangular intersection of the widget's plane with every ancestor's plane and the terminal viewport. The result is the on-screen rectangle into which the widget could safely paint pixels. Empty when the widget is fully outside any ancestor or off the terminal. Used by `Image.render` to decide whether to emit the sprixel. Reading from notcurses each call (rather than from cached Widget abs-y/x) means we don't depend on the Widget cache being in sync with the actual notcurses plane positions — which can desync any time something moves a plane outside the normal layout cascade (Container.park reposition cascade, direct ncplane_move_yx, etc). Notcurses position is the source of truth for sprixel visibility because that's where pixels actually paint.

### sub compute-clip-only-blit

```raku
sub compute-clip-only-blit(
    Int :$self-rows! where { ... },
    Int :$self-cols! where { ... },
    Int :$cell-px-y! where { ... },
    Int :$cell-px-x! where { ... },
    Int :$rcelly! where { ... },
    Int :$rcellx! where { ... },
    Int :$dest-y!,
    Int :$dest-x!,
    Int :$source-row!,
    Int :$source-col!,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Hash
```

Pure math for `Image.render-viewport-crop`'s `:clip-only` path. Given the widget's cell rect, the cell-pixel dims, the image's natural rendered cell footprint (rcelly / rcellx) — as reported by notcurses for the visual blitted at the FULL widget rect — and the caller's visible-cell window (source-row + rows in widget cells, source-col + cols horizontally), returns either an empty Hash (visible cells = 0, no blit) or the full set of blit parameters: =item **begy**, **begx** — source pixel crop origin, in pixels of the `cell-aligned pre-scaled` visual (rcelly × cell-px-y by rcellx × cell-px-x). Since the source is cell-aligned, every cell row of the image is exactly `cell-px-y` source pixels tall. =item **leny**, **lenx** — source pixel crop length. =item **blit-rows**, **blit-cols** — dest plane cell dims. =item **blit-dest-y**, **blit-dest-x** — dest plane position within the parent plane (parent = the caller's `$parent-plane`), as `dest-y + (vis-cell-y-start - source-row)` and the analogous `x`. `dest-y`/`dest-x` are the visible-viewport offsets the caller already computed. The output dims have the invariant that **lenx = blit-cols × cell-px-x** and **leny = blit-rows × cell-px-y**, which is what makes `NCSCALE_STRETCH` render the source crop into the dest plane at exactly 1:1 — no scale_visual call, no aspect drift. Width-invariance across vertical scroll positions follows from the fact that `blit-cols` and `lenx` only depend on `self-cols`, `rcellx`, `source-col` and `cols` — never on `source-row` or `rows`. Exported so the test suite can exercise the math without spinning up notcurses.

