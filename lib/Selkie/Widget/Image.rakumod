=begin pod

=head1 NAME

Selkie::Widget::Image - Display an image via notcurses pixel graphics

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Image;
use Selkie::Sizing;

my $img = Selkie::Widget::Image.new(
    file   => 'avatar.png',
    sizing => Sizing.fixed(20),
);

$img.set-file('new-avatar.png');
$img.clear-image;

=end code

=head1 DESCRIPTION

Loads and renders an image file onto its plane. If the terminal supports
pixel graphics — Sixel, Kitty graphics protocol, iTerm2 inline images
(notcurses unifies all three behind C<NCBLIT_PIXEL>) — full-resolution
pixels are rendered. Otherwise notcurses falls back to Unicode block /
quadrant / braille art.

=head2 Rendering model

C<Image.render> is a pure function of three inputs:

=item Source file content (the PNG / JPEG path).
=item The Image's own plane's notcurses-tracked screen rectangle (live, queried each render via C<ncplane_abs_y> / C<ncplane_dim_yx>).
=item The chain of ancestor plane rectangles up to the terminal viewport (also queried via notcurses each render).

Every user-visible state change — a parent scrolling, a sibling card
resizing the layout, a terminal zoom, a modal mounting — flows through
Selkie's dirty-propagation framework (C<set-viewport>, C<handle-resize>,
C<Container.!render-children>) and triggers C<Image.render> via the
normal dirty-driven render walk.

The render does exactly one thing: if the Image's plane is fully
contained in every ancestor's plane and within the terminal viewport,
emit the sprixel. Otherwise, ensure no live blit exists and skip. There
is no "park" position, no Widget-cache visibility check, no per-Image
state machine — just a notcurses-driven bounds intersection.

=head2 Why notcurses, not Widget cache, for visibility decisions

Selkie keeps two parallel position states for every widget: the Widget
attributes (C<$.abs-y>, C<$.abs-x>, C<$.rows>, C<$.cols>) updated by
parent layouts via C<set-viewport> / C<handle-resize>, and the
notcurses plane position updated by C<ncplane_move_yx> and notcurses's
internal C<move_bound_planes> cascade. For text widgets these stay in
sync because cell ops are bounded by the plane and any divergence is
invisible. For sprixels they catastrophically diverge — sprixel pixels
paint at notcurses-tracked coordinates, and any cache desync produces
blits at the wrong place.

So Image's visibility decision queries notcurses directly. Widget
cache is fine for everything else.

=head2 Park

C<park> destroys the blit-plane and does nothing else. C<Container.park>
in the ancestor chain handles moving planes off-screen via its
reposition cascade; notcurses's C<move_bound_planes> carries the
Image's plane along with the ancestor moves. When the cascade later
unparks (e.g., a card scrolls back into view), the dirty-driven render
walk reaches Image, the visibility check sees the now-on-screen
notcurses position, and a fresh blit is emitted.

=head2 Pixel bleed protection

Notcurses doesn't clip child planes' pixels to ancestor bounds. The
"fully contained in every ancestor" gate replaces any clipping —
Image is hidden during partial overlap rather than emitting pixels
that could bleed past an ancestor's edge. Partial-clip rendering
(showing the visible portion only) is intentionally out of scope for
this version; can be added later via Vips-based source cropping.

There's a second, protocol-specific source of bleed: Sixel emits
pixels in 6-pixel-tall groups, so a sprixel always rounds UP to the
next multiple of 6 vertical pixels on the wire. When the cell pixel
height isn't a multiple of 6, that rounding paints a few pixels
beyond the plane's pixel rectangle and into the next cell row. C<!emit-blit>
detects the active pixel implementation and shrinks the blit-plane
vertically by at most one cell when the protocol has a > 1 vertical
granularity, so the rounded-up pixel emit always fits inside Image's
own plane. Kitty graphics protocol and iTerm2 inline images use
exact pixel sizes (granularity 1); for those, no shrinkage applies.

=head1 EXAMPLES

=head2 Preview in a Split

=begin code :lang<raku>

my $preview = Selkie::Widget::Image.new(sizing => Sizing.flex);
my $border  = Selkie::Widget::Border.new(title => 'Preview', sizing => Sizing.flex);
$border.set-content($preview);

$preview.set-file($selected-path);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Border> — wrap to contain visual bleed of cell content
=item L<Selkie::EffectiveBounds> — value class returned by the bounds intersection helper

=end pod

use NativeCall;

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Visual;
use Notcurses::Native::Plane;
use Notcurses::Native::Context;

use Selkie::Widget;
use Selkie::EffectiveBounds;
use Selkie::Tree;

unit class Selkie::Widget::Image does Selkie::Widget;

# --- Debug logging (env-var-gated) -----------------------------------------
#
# Writes via spurt :append rather than $*ERR / `note`, because Selkie::App
# uses dup2(2, log-fd) to redirect stderr — and Raku's $*ERR can have its
# own buffering that doesn't always follow the dup2 cleanly. Going direct
# to a known file path side-steps the question.
#
# SELKIE_IMAGE_DEBUG=1            → /tmp/selkie-image-debug.{pid}.log
# SELKIE_IMAGE_DEBUG=/path/to/log → that path
# unset / empty / "0"             → no logging.
my Str  $LOG-PATH;
my Bool $LOG-INITIALIZED = False;

has Str $!file;
has NcvisualHandle $!visual;
has Bool $!loaded = False;
has NcplaneHandle $!blit-plane;

# Clip-only mode pre-scales C<$!visual> to its B<cell-aligned> natural
# rendering pixel dims — i.e. (rcelly × cell-px-y) tall by
# (rcellx × cell-px-x) wide — so that every image cell row maps to
# exactly cell-px-y source pixels and partial-clip renders use pure
# integer pixel math (no aspect drift). Cache invalidates whenever
# the widget's natural rendering dims change (terminal resize, widget
# cols/rows change); reload-from-file before re-scale to avoid
# compounding interpolation loss from repeated downscales of an
# already-downscaled visual.
has UInt $!visual-scaled-rpix-y = 0;
has UInt $!visual-scaled-rpix-x = 0;

#|( When True, partial-clip rendering (C<render-viewport-crop>, called by
    row-scrolling containers like C<ViewportedCardList>) preserves the
    image's natural scale and on-screen position: the image is rendered
    as it would appear when fully visible, and rows / columns outside the
    visible viewport are simply not emitted. Defaults to False — the
    standard behaviour, where the visible cell rectangle is filled with
    a scaled-down crop of the source.

    Use this when you have a stack of images inside a row-scrolling list
    and want the picture to feel pinned to its host card rather than
    breathing in and out as the card slides past the viewport edge. The
    cost is that fully-clipped images (no visible cells overlap the
    natural image rectangle) produce no output — exactly the desired
    behaviour, but worth knowing. )
has Bool $.clip-only = False;

#|( Cached state from the previous successful blit. Compared each render
    against the live notcurses values; when they diverge we tear down +
    re-blit. Cleared by C<destroy-blit-plane>. )
has Int  $!last-abs-y;
has Int  $!last-abs-x;
has UInt $!last-rows = 0;
has UInt $!last-cols = 0;
has UInt $!last-cell-px-y = 0;
has UInt $!last-cell-px-x = 0;
has Str  $!last-file;

#| Height in rows. Same as C<self.rows>; provided for the ScrollView contract.
method logical-height(--> UInt) { self.rows }

#|( React to a parent layout's resize cascade by updating own dimensions
    and marking dirty. We always mark dirty even when our own dims didn't
    change — handle-resize fires from ancestor state changes that may
    affect our visibility chain even without changing our own size, and
    a redundant render that hits the unchanged cache is essentially free
    (one rect-intersection walk + one snapshot diff). )
method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    self.resize($rows, $cols) if $changed;
    self.mark-dirty;
}

#| The currently displayed file path, or C<Nil>.
method file(--> Str) { $!file }

#| True when an active blit-plane currently exists.
method has-blit-plane(--> Bool) { $!blit-plane.defined }

#| Swap the displayed image. No-op if the same path is already loaded.
#| Triggers a re-blit on the next render via the dirty cascade.
method set-file(Str $path) {
    return if $path eq ($!file // '');
    self!unload;
    $!file = $path;
    self.mark-dirty;
}

#| Unload the current image and clear the widget.
method clear-image() {
    self!unload;
    $!file = Str;
    self.mark-dirty;
}

method !load() {
    return if $!loaded;
    return without $!file;
    $!visual = ncvisual_from_file($!file);
    $!loaded = $!visual.defined;
    # A fresh load wipes any prior pre-scaling, so the cache markers
    # need to reset too — otherwise the next render thinks the visual
    # is still at its pre-scale dims and skips a needed re-scale.
    $!visual-scaled-rpix-y = 0;
    $!visual-scaled-rpix-x = 0;
}

#|( For the clip-only render path: ensure C<$!visual>'s pixel
    dimensions equal the natural rendering dims (the dims notcurses's
    NCSCALE_SCALE would produce when blitting the original source into
    the full widget cell rect). When this holds, NCSCALE_NONE blits
    source pixels 1:1 to dest pixels, so partial-clip renders are
    pixel-exact regardless of source-crop aspect — no NCSCALE_SCALE
    letterbox drift per scroll step.

    Returns True iff C<$!visual> is now at natural dims and ready for
    NCSCALE_NONE blits. )
#|( For the clip-only render path: pre-scale C<$!visual> to its
    B<cell-aligned> natural rendering dimensions — i.e.
    C<rcelly × cell-px-y> tall by C<rcellx × cell-px-x> wide. After
    this, every image cell row is exactly C<cell-px-y> source pixels
    tall (and similarly for cols), so the per-frame source-crop math
    in C<render-viewport-crop>'s clip-only branch is pure integer
    arithmetic with no rounding drift, and a source crop of N image
    cell rows is exactly N × cell-px-y source pixels — which matches
    the dest blit plane's pixel rect of N cells × cell-px-y.

    Returns True iff the visual is now at cell-aligned dims and ready
    for C<NCSCALE_STRETCH> blits that render 1:1.

    The cache invalidates whenever the widget's natural cell footprint
    changes (terminal resize / widget cols/rows change), at which point
    we reload from the source file to avoid compounding interpolation
    loss from repeated re-scaling of an already-downscaled visual. )
method !ensure-scaled-visual($nc, UInt $cell-px-y, UInt $cell-px-x --> Bool) {
    return False unless $!loaded && $!visual.defined;

    # Probe geom against the CURRENT visual to find the natural cell
    # footprint (rcelly / rcellx). These are notcurses-computed and
    # account for cell-px geometry of the parent pile.
    my $geom = Ncvgeom.new;
    my $probe = NcvisualOptions.new(scaling => NCSCALE_SCALE, blitter => NCBLIT_PIXEL);
    $probe.set-plane(self.plane);
    ncvisual_geom($nc, $!visual, $probe, $geom);

    # Target: cell-aligned natural rendering size.
    my UInt $target-y = ($geom.rcelly.UInt * $cell-px-y);
    my UInt $target-x = ($geom.rcellx.UInt * $cell-px-x);
    return False if $target-y == 0 || $target-x == 0;

    # Already at the right dims — either we pre-scaled to this exact
    # size in a prior call, or the source happens to match natively.
    if $geom.pixy == $target-y && $geom.pixx == $target-x {
        $!visual-scaled-rpix-y = $target-y;
        $!visual-scaled-rpix-x = $target-x;
        return True;
    }

    # Either never scaled, or widget dims changed. Reload from file to
    # get the original-resolution source, then re-scale to the new
    # cell-aligned target. Reload-before-scale matters: repeatedly
    # resizing an already-resized visual compounds interpolation loss.
    self!unload;
    self!load;
    return False unless $!loaded;

    ncvisual_resize_noninterpolative($!visual, $target-y, $target-x);
    $!visual-scaled-rpix-y = $target-y;
    $!visual-scaled-rpix-x = $target-x;
    self!debug-log("ensure-scaled-visual",
        :target-y($target-y), :target-x($target-x),
        :rcelly($geom.rcelly), :rcellx($geom.rcellx),
        :cell-px-y($cell-px-y), :cell-px-x($cell-px-x));
    True;
}

method !unload() {
    if $!visual {
        ncvisual_destroy($!visual);
        $!visual = NcvisualHandle;
    }
    $!loaded = False;
}

#|( Tear down the current blit-plane and clear the cached state. Sets
    the underlying notcurses sprixel to SPRIXEL_HIDE; the actual
    sprixel-remove escape goes out at the next end-of-frame
    notcurses_render, where rasterize_sprixels() processes every
    SPRIXEL_HIDE before any SPRIXEL_INVALIDATED in a single pass. So a
    destroy + create within the same frame produces the correct wire
    sequence — no mid-walk render needed.

    Idempotent: returns immediately if no live blit. Note the C<without>
    test is on C<$!blit-plane> directly, NOT C<$!blit-plane.defined> —
    the latter returns a Bool which is always defined, so C<without
    Bool> never fires the early-return. Subtle Raku gotcha. )
method destroy-blit-plane(--> Nil) {
    return without $!blit-plane;
    # Capture the blit plane's absolute screen rectangle BEFORE
    # destroying it. After destruction the handle is gone and notcurses
    # forgets the geometry, but the cells where the sprixel was painted
    # still need to be repainted by the widgets that own them —
    # otherwise the parent's last-rendered cell content stays on screen
    # under where the sprixel was, and (worse on Kitty graphics)
    # framework-side cell ops won't fire to overwrite any pixel
    # residue near the sprixel's emit area.
    my Int $blit-abs-y = ncplane_abs_y($!blit-plane);
    my Int $blit-abs-x = ncplane_abs_x($!blit-plane);
    my uint32 $blit-rows = 0; my uint32 $blit-cols = 0;
    ncplane_dim_yx($!blit-plane, $blit-rows, $blit-cols);

    ncplane_destroy($!blit-plane);
    $!blit-plane = NcplaneHandle;
    $!last-rows  = 0;
    $!last-cols  = 0;
    $!last-abs-y = Int;
    $!last-abs-x = Int;
    $!last-file  = Str;
    $!last-cell-px-y = 0;
    $!last-cell-px-x = 0;

    # Mark every widget whose plane intersects the now-destroyed
    # sprixel's screen rect as dirty so they repaint their cells.
    # Without this, the next frame happily skips painting (everyone
    # is clean) and any stale framebuffer cells left in the wake of
    # the sprixel — particularly visible near the cards container's
    # bottom border when an image scrolls off the top of a row-
    # scrolling viewport — survive.
    if $blit-rows > 0 && $blit-cols > 0 {
        mark-widgets-in-rect-dirty(
            abs-y => $blit-abs-y,
            abs-x => $blit-abs-x,
            rows  => $blit-rows.UInt,
            cols  => $blit-cols.UInt,
        );
    }

    self!debug-log("destroy-blit-plane",
        :abs-y($blit-abs-y), :abs-x($blit-abs-x),
        :rows($blit-rows.UInt), :cols($blit-cols.UInt));
}

#|( Park: destroy the blit-plane. Container.park's reposition cascade
    handles moving the plane off-screen — notcurses's move_bound_planes
    carries this Image's plane along with the ancestor moves. The next
    dirty-driven render reaches us via the cascade, the visibility
    chain sees the off-screen notcurses position, and the emit is
    skipped. When ancestors unpark (e.g., a card scrolls back into
    view), the dirty cascade fires again, the visibility check sees
    the on-screen notcurses position, and a fresh blit emits. )
method park() {
    self!debug-log("park");
    self.destroy-blit-plane;
}

#| Tear down the sprixel and the underlying ncvisual / blit plane,
#| then destroy the widget's own plane. Always called on app shutdown
#| or when the widget is explicitly removed; sprixel cleanup is
#| critical because notcurses won't auto-evict pixels left on the
#| terminal when their carrier plane goes away.
method destroy() {
    self.destroy-blit-plane;
    self!unload;
    self!destroy-plane;
}

#| Per-frame render. When the source file is unset / unloadable, paints
#| a fallback message in dim text. When occluded by a modal or off
#| the visible region, ensures any prior sprixel is torn down before
#| returning. The blit plane is created lazily on the first render
#| that actually emits pixels.
method render() {
    return without self.plane;
    ncplane_resize_simple(self.plane, self.rows, self.cols);
    ncplane_erase(self.plane);

    self!load;
    unless $!loaded {
        my $style = self.theme.text-dim;
        self.apply-style($style);
        my $msg = $!file.defined ?? "Cannot load: {$!file.IO.basename}" !! "No image";
        ncplane_putstr_yx(self.plane, self.rows div 2, 1, $msg);
        self!debug-log("render-fallback", :file($!file));
        self!ensure-no-blit;
        self.clear-dirty;
        return;
    }

    if self!is-occluded-by-modal {
        self!debug-log("render-occluded");
        self!ensure-no-blit;
        self.clear-dirty;
        return;
    }

    # Clip-only images live inside a row-scrolling container (e.g.
    # ViewportedCardList) which drives the sprixel exclusively via
    # render-viewport-crop. Image.render's own emit-blit must NOT
    # fire in that case: it would create a competing sprixel as a
    # child of Image's own plane (in the container's backing chain,
    # which gets parked off-screen at end-of-frame). That competing
    # plane survives past render-viewport-crop's destroy + replace
    # (because emit-blit's plane is in a different parent chain than
    # render-viewport-crop's plane), leaving a leftover sprixel that
    # notcurses moves with the parked backing chain and emits at the
    # wrong screen row — visible as a one-row ghost over the
    # container's bottom border the moment the card scrolls fully
    # off the top. render-viewport-crop is the single canonical
    # blit pathway for clip-only images.
    if $!clip-only {
        self!debug-log("render-clip-only-defer");
        self!ensure-no-blit;
        self.clear-dirty;
        return;
    }

    # Authoritative bounds via notcurses chain. We read the position +
    # dimensions of every plane in the ancestor chain directly from
    # notcurses (live values, never the Widget cache that can desync
    # from notcurses when ancestors move via Container.park or other
    # cascades). The intersection with the terminal viewport is the
    # final clip.
    my $rect = effective-screen-rect-for(self);
    my Int $own-y = ncplane_abs_y(self.plane);
    my Int $own-x = ncplane_abs_x(self.plane);

    # Full-containment check: Image renders only when its entire plane
    # fits inside every ancestor and within the terminal. Partial
    # overlap (e.g., a card half-clipped at the top of CardList while
    # scrolling past) hides the Image until it's fully back in bounds.
    # This is intentional for v1 — partial-clip rendering can be added
    # later via Vips-based source cropping; the priority here is
    # correctness (no bleed past ancestor borders).
    my Bool $fully-contained = $rect.rows == self.rows
                            && $rect.cols == self.cols
                            && $rect.abs-y == $own-y
                            && $rect.abs-x == $own-x;

    unless $fully-contained {
        self!debug-log("render-clipped",
            :own-y($own-y), :own-x($own-x),
            :own-rows(self.rows), :own-cols(self.cols),
            :rect-y($rect.abs-y), :rect-x($rect.abs-x),
            :rect-rows($rect.rows), :rect-cols($rect.cols));
        self!ensure-no-blit;
        self.clear-dirty;
        return;
    }

    # Cache diff — same fields as before but anchored on live notcurses
    # values. cell-px shifts (font zoom) trigger a re-blit even when
    # cell footprint is unchanged.
    my uint32 $pxy = 0; my uint32 $pxx = 0;
    my uint32 $cdy = 0; my uint32 $cdx = 0;
    my uint32 $bmy = 0; my uint32 $bmx = 0;
    ncplane_pixel_geom(self.plane, $pxy, $pxx, $cdy, $cdx, $bmy, $bmx);
    my UInt $cell-px-y = $cdy.UInt;
    my UInt $cell-px-x = $cdx.UInt;

    my Bool $unchanged = $!blit-plane.defined
        && $!last-abs-y.defined && $own-y == $!last-abs-y
        && $!last-abs-x.defined && $own-x == $!last-abs-x
        && self.rows == $!last-rows
        && self.cols == $!last-cols
        && $cell-px-y == $!last-cell-px-y
        && $cell-px-x == $!last-cell-px-x
        && ($!file // '') eq ($!last-file // '');

    if $unchanged {
        self!debug-log("render-cache-hit");
        self.clear-dirty;
        return;
    }

    self!debug-log("render-reblit",
        :own-y($own-y), :own-x($own-x),
        :rows(self.rows), :cols(self.cols),
        :cell-px-y($cell-px-y), :cell-px-x($cell-px-x));

    self.destroy-blit-plane;
    self!emit-blit;

    $!last-abs-y     = $own-y;
    $!last-abs-x     = $own-x;
    $!last-rows      = self.rows;
    $!last-cols      = self.cols;
    $!last-cell-px-y = $cell-px-y;
    $!last-cell-px-x = $cell-px-x;
    $!last-file      = $!file;

    self.clear-dirty;
}

#|( Internal hook for row-viewport containers that render children into an
    offscreen logical plane and then composite only a visible cell slice.
    Normal Image.render intentionally hides partially clipped sprixels to
    prevent bleed; this hook performs an explicit source crop and blits
    the visible rectangle directly into the caller's viewport plane. )
method render-viewport-crop(
    NcplaneHandle :$parent-plane!,
    Int :$dest-y!,
    Int :$dest-x!,
    Int :$source-row!,
    Int :$source-col = 0,
    UInt :$rows!,
    UInt :$cols!,
    --> Bool
) {
    return False without self.plane;
    self!load;
    return False unless $!loaded;

    self.destroy-blit-plane;

    my $nc = ncplane_notcurses($parent-plane);
    my $pixel-impl = notcurses_check_pixel_support($nc);
    my $blitter = $pixel-impl > 0 ?? NCBLIT_PIXEL
                                  !! ncvisual_media_defblitter($nc, NCSCALE_SCALE);

    my uint32 $pxy = 0; my uint32 $pxx = 0;
    my uint32 $cdy = 0; my uint32 $cdx = 0;
    my uint32 $bmy = 0; my uint32 $bmx = 0;
    ncplane_pixel_geom($parent-plane, $pxy, $pxx, $cdy, $cdx, $bmy, $bmx);
    my UInt $cell-px-y = $cdy.UInt max 1;
    my UInt $cell-px-x = $cdx.UInt max 1;

    my $geom = Ncvgeom.new;
    my $probe = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
    $probe.set-plane(self.plane);
    ncvisual_geom($nc, $!visual, $probe, $geom);

    my UInt $src-total-y = $geom.pixy.UInt max ($cell-px-y * (self.rows max 1));
    my UInt $src-total-x = $geom.pixx.UInt max ($cell-px-x * (self.cols max 1));

    my (UInt $begy, UInt $begx, UInt $leny, UInt $lenx);
    my (Int $blit-dest-y, Int $blit-dest-x);
    my (UInt $blit-rows, UInt $blit-cols);

    my Int $blit-scaling;

    if $!clip-only {
        # Clip-only path: pre-scale the visual to cell-aligned natural
        # dims (so every image cell row is exactly cell-px-y source
        # pixels tall), then ask the pure-function helper for the
        # blit parameters. NCSCALE_STRETCH blits the source crop into
        # a plane whose pixel rect equals the crop's pixel rect — 1:1
        # rendering, no aspect drift, no scale_visual call.
        self!ensure-scaled-visual($nc, $cell-px-y, $cell-px-x);

        # Re-probe geom against the now-cell-aligned visual; rcelly
        # and rcellx are now `pixy / cell-px-y` and `pixx / cell-px-x`
        # exactly.
        ncvisual_geom($nc, $!visual, $probe, $geom);

        my %r = compute-clip-only-blit(
            self-rows  => self.rows,    self-cols  => self.cols,
            cell-px-y  => $cell-px-y,   cell-px-x  => $cell-px-x,
            rcelly     => $geom.rcelly.UInt, rcellx => $geom.rcellx.UInt,
            dest-y     => $dest-y,      dest-x     => $dest-x,
            source-row => $source-row,  source-col => $source-col,
            rows       => $rows,        cols       => $cols,
        );

        unless %r {
            # Image is entirely outside the visible viewport — emit
            # nothing. The destroy-blit-plane at the top of the method
            # already tore down any previous frame's blit-plane.
            $!last-rows = 0;
            $!last-cols = 0;
            self.clear-dirty;
            return True;
        }

        $begy        = %r<begy>;
        $begx        = %r<begx>;
        $leny        = %r<leny>;
        $lenx        = %r<lenx>;
        $blit-rows   = %r<blit-rows>;
        $blit-cols   = %r<blit-cols>;
        $blit-dest-y = %r<blit-dest-y>;
        $blit-dest-x = %r<blit-dest-x>;
        $blit-scaling = NCSCALE_STRETCH;
    } else {
        $begy = (($source-row max 0) * $src-total-y / (self.rows max 1)).floor.UInt;
        $begx = (($source-col max 0) * $src-total-x / (self.cols max 1)).floor.UInt;
        $leny = ($rows * $src-total-y / (self.rows max 1)).ceiling.UInt max 1;
        $lenx = ($cols * $src-total-x / (self.cols max 1)).ceiling.UInt max 1;
        $leny = $leny min ($src-total-y - $begy) if $begy < $src-total-y;
        $lenx = $lenx min ($src-total-x - $begx) if $begx < $src-total-x;
        $blit-dest-y = $dest-y;
        $blit-dest-x = $dest-x;
        $blit-rows   = $rows;
        $blit-cols   = $cols;
        $blit-scaling = NCSCALE_SCALE;
    }

    # Sixel granularity rounding: sixel emits in 6-px-tall bands, so the
    # blit plane's pixel height has to be a multiple of 6 or the bottom
    # band is dropped. Round down rather than up so the actual rendered
    # area stays within the plane's cell footprint; on a sixel terminal
    # this costs at most one band off the bottom edge.
    my UInt $dest-rows = $blit-rows;
    my UInt $gran-y = $pixel-impl == NCPIXEL_SIXEL ?? 6 !! 1;
    if $gran-y > 1 && $cell-px-y > 0 {
        my UInt $own-px = $blit-rows * $cell-px-y;
        my UInt $max-emit-px = ($own-px div $gran-y) * $gran-y;
        my UInt $max-rows = ($max-emit-px div $cell-px-y) max 1;
        $dest-rows = $dest-rows min $max-rows;
    }

    my $opts = NcplaneOptions.new(
        y => $blit-dest-y, x => $blit-dest-x,
        rows => $dest-rows, cols => $blit-cols,
    );
    $!blit-plane = ncplane_create($parent-plane, $opts);
    return True without $!blit-plane;

    my $vopts = NcvisualOptions.new(
        scaling => $blit-scaling,
        :$blitter,
        :$begy, :$begx, :$leny, :$lenx,
    );
    $vopts.set-plane($!blit-plane);
    my $result = ncvisual_blit($nc, $!visual, $vopts);

    if !$result.defined && $blitter == NCBLIT_PIXEL {
        $blitter = ncvisual_media_defblitter($nc, $blit-scaling);
        $vopts = NcvisualOptions.new(
            scaling => $blit-scaling,
            :$blitter,
            :$begy, :$begx, :$leny, :$lenx,
        );
        $vopts.set-plane($!blit-plane);
        $result = ncvisual_blit($nc, $!visual, $vopts);
    }

    if !$result.defined {
        $vopts = NcvisualOptions.new(
            scaling => $blit-scaling,
            blitter => NCBLIT_1x1,
            :$begy, :$begx, :$leny, :$lenx,
        );
        $vopts.set-plane($!blit-plane);
        ncvisual_blit($nc, $!visual, $vopts);
    }

    $!last-rows = 0;
    $!last-cols = 0;
    self.clear-dirty;
    True;
}

method !ensure-no-blit() {
    self.destroy-blit-plane if $!blit-plane;
}

method !is-occluded-by-modal(--> Bool) {
    my $modal = current-active-modal();
    return False without $modal;
    my $p = self.parent;
    while $p.defined {
        return False if $p === $modal;
        $p = $p.parent;
    }
    True;
}

#|( Create a fresh blit-plane sized to the Image's full plane area at
    offset (0, 0) and blit the loaded visual into it. Called from
    render() only when the visibility check passed (Image is fully
    contained in every ancestor) — so we know we can emit the entire
    image without bleeding past anything. )
method !emit-blit(--> Nil) {
    my $nc = self!notcurses-handle;

    my $pixel-impl = notcurses_check_pixel_support($nc);
    my $blitter    = $pixel-impl > 0 ?? NCBLIT_PIXEL
                                     !! ncvisual_media_defblitter($nc, NCSCALE_SCALE);

    my $geom = Ncvgeom.new;
    my $probe = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
    $probe.set-plane(self.plane);
    ncvisual_geom($nc, $!visual, $probe, $geom);

    # Cap the rendered cell footprint at our own plane size. Defensive
    # against notcurses geometry rounding up — the cap means the
    # blit-plane never exceeds Image's plane in cells, which combined
    # with the visibility check (Image fully contained in ancestors)
    # keeps the cell footprint bounded.
    my UInt $img-rows = ($geom.rcelly min self.rows) max 1;
    my UInt $img-cols = ($geom.rcellx min self.cols) max 1;

    # Sprixel pixel-rounding cap. Even when the blit-plane is bounded in
    # CELLS to our own plane, the actual pixel emit on the wire can
    # exceed cell boundaries depending on the pixel protocol:
    #
    #   * Sixel groups pixels into 6-pixel-tall sixels — the wire
    #     format always emits a multiple of 6 vertical pixels. So a
    #     blit of N rows × cell-px-y pixels gets rounded UP to the
    #     next multiple of 6, painting up to 5 pixels below the
    #     plane's pixel rectangle. Those extra pixels land in cells
    #     OUTSIDE Image's plane (typically the avatar's backdrop
    #     colour over whatever's beneath — bottom border, next card,
    #     etc.).
    #
    #   * Kitty graphics protocol + iTerm2 inline images use exact
    #     pixel sizes (granularity 1) — no rounding, no overflow.
    #
    # When the protocol has > 1 vertical granularity, shrink blit-rows
    # so that ceil(rows × cell-px-y / gran) × gran ≤ self.rows ×
    # cell-px-y. The image renders into a slightly smaller cell
    # footprint, centered, and pixels stay inside our plane.
    my UInt $gran-y = $pixel-impl == NCPIXEL_SIXEL ?? 6 !! 1;
    if $gran-y > 1 {
        my uint32 $pxy0 = 0; my uint32 $pxx0 = 0;
        my uint32 $cdy0 = 0; my uint32 $cdx0 = 0;
        my uint32 $bmy0 = 0; my uint32 $bmx0 = 0;
        ncplane_pixel_geom(self.plane, $pxy0, $pxx0, $cdy0, $cdx0, $bmy0, $bmx0);
        my UInt $cell-px-y = $cdy0.UInt;
        if $cell-px-y > 0 {
            # Largest blit-rows where the rounded-up pixel emit fits
            # within our own pixel rectangle.
            my UInt $own-px      = self.rows * $cell-px-y;
            my UInt $max-emit-px = ($own-px div $gran-y) * $gran-y;
            my UInt $max-rows    = ($max-emit-px div $cell-px-y) max 1;
            $img-rows = $img-rows min $max-rows;
        }
    }

    my UInt $offset-y = ($img-rows < self.rows) ?? (self.rows - $img-rows) div 2 !! 0;
    my UInt $offset-x = ($img-cols < self.cols) ?? (self.cols - $img-cols) div 2 !! 0;

    my $opts = NcplaneOptions.new(
        y => $offset-y, x => $offset-x,
        rows => $img-rows, cols => $img-cols,
    );
    $!blit-plane = ncplane_create(self.plane, $opts);

    my $vopts = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
    $vopts.set-plane($!blit-plane);

    my $result = ncvisual_blit($nc, $!visual, $vopts);

    if !$result.defined && $blitter == NCBLIT_PIXEL {
        $blitter = ncvisual_media_defblitter($nc, NCSCALE_SCALE);
        $vopts = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
        $vopts.set-plane($!blit-plane);
        $result = ncvisual_blit($nc, $!visual, $vopts);
    }

    if !$result.defined {
        $vopts = NcvisualOptions.new(scaling => NCSCALE_SCALE, blitter => NCBLIT_1x1);
        $vopts.set-plane($!blit-plane);
        ncvisual_blit($nc, $!visual, $vopts);
    }
}

method !notcurses-handle(--> NotcursesHandle) {
    ncplane_notcurses(self.plane);
}

method !debug-log(Str:D $stage, *%kv --> Nil) {
    unless $LOG-INITIALIZED {
        $LOG-INITIALIZED = True;
        my $env = %*ENV<SELKIE_IMAGE_DEBUG>;
        if $env.defined && $env.chars > 0 && $env ne '0' {
            $LOG-PATH = ($env eq '1' || $env.lc eq 'true')
                ?? "/tmp/selkie-image-debug.{$*PID}.log"
                !! $env;
            my $parent = $LOG-PATH.IO.parent;
            try $parent.mkdir unless $parent.e;
            try spurt $LOG-PATH,
                "=== selkie image debug pid={$*PID} {DateTime.now.truncated-to('second')} ===\n",
                :append;
        }
    }
    return without $LOG-PATH;
    my @parts = "[selkie:image:$stage]";
    @parts.push: "id={self.widget-id}";
    for %kv.kv -> $k, $v {
        @parts.push: "$k={$v // 'Nil'}";
    }
    try spurt $LOG-PATH, "{@parts.join(' ')}\n", :append;
}

#|( Walk the widget's parent chain via notcurses queries (NOT Widget
    cache) and return the rectangular intersection of the widget's
    plane with every ancestor's plane and the terminal viewport. The
    result is the on-screen rectangle into which the widget could
    safely paint pixels. Empty when the widget is fully outside any
    ancestor or off the terminal.

    Used by C<Image.render> to decide whether to emit the sprixel.
    Reading from notcurses each call (rather than from cached Widget
    abs-y/x) means we don't depend on the Widget cache being in sync
    with the actual notcurses plane positions — which can desync any
    time something moves a plane outside the normal layout cascade
    (Container.park reposition cascade, direct ncplane_move_yx, etc).
    Notcurses position is the source of truth for sprixel visibility
    because that's where pixels actually paint. )
sub effective-screen-rect-for(Selkie::Widget $w --> Selkie::EffectiveBounds) is export {
    return Selkie::EffectiveBounds.new(
        abs-y => 0, abs-x => 0, rows => 0, cols => 0,
    ) without $w.plane;

    my Int  $cur-y = ncplane_abs_y($w.plane);
    my Int  $cur-x = ncplane_abs_x($w.plane);
    my uint32 $h0 = 0; my uint32 $w0 = 0;
    ncplane_dim_yx($w.plane, $h0, $w0);
    my UInt $cur-h = $h0.UInt;
    my UInt $cur-w = $w0.UInt;

    my $ancestor = $w.parent;
    while $ancestor.defined && $ancestor.plane && !($cur-h == 0 || $cur-w == 0) {
        my Int $py = ncplane_abs_y($ancestor.plane);
        my Int $px = ncplane_abs_x($ancestor.plane);
        my uint32 $ph = 0; my uint32 $pw = 0;
        ncplane_dim_yx($ancestor.plane, $ph, $pw);

        my Int $top    = $cur-y max $py;
        my Int $left   = $cur-x max $px;
        my Int $bottom = ($cur-y + $cur-h.Int) min ($py + $ph.Int);
        my Int $right  = ($cur-x + $cur-w.Int) min ($px + $pw.Int);
        $cur-y = $top;
        $cur-x = $left;
        $cur-h = (($bottom - $top) max 0).UInt;
        $cur-w = (($right  - $left) max 0).UInt;
        $ancestor = $ancestor.parent;
    }

    my ($vp-rows, $vp-cols) = terminal-viewport();
    my Int $tb = $vp-rows.Int;
    my Int $tr = $vp-cols.Int;
    my Int $top    = $cur-y max 0;
    my Int $left   = $cur-x max 0;
    my Int $bottom = ($cur-y + $cur-h.Int) min $tb;
    my Int $right  = ($cur-x + $cur-w.Int) min $tr;
    Selkie::EffectiveBounds.new(
        abs-y => $top, abs-x => $left,
        rows  => (($bottom - $top) max 0).UInt,
        cols  => (($right  - $left) max 0).UInt,
    );
}

#|( Pure math for C<Image.render-viewport-crop>'s C<:clip-only> path.

    Given the widget's cell rect, the cell-pixel dims, the image's
    natural rendered cell footprint (rcelly / rcellx) — as reported by
    notcurses for the visual blitted at the FULL widget rect — and the
    caller's visible-cell window (source-row + rows in widget cells,
    source-col + cols horizontally), returns either an empty Hash
    (visible cells = 0, no blit) or the full set of blit parameters:

    =item B<begy>, B<begx> — source pixel crop origin, in pixels of the
      C<cell-aligned pre-scaled> visual (rcelly × cell-px-y by rcellx ×
      cell-px-x). Since the source is cell-aligned, every cell row of
      the image is exactly C<cell-px-y> source pixels tall.
    =item B<leny>, B<lenx> — source pixel crop length.
    =item B<blit-rows>, B<blit-cols> — dest plane cell dims.
    =item B<blit-dest-y>, B<blit-dest-x> — dest plane position within
      the parent plane (parent = the caller's C<$parent-plane>), as
      C<dest-y + (vis-cell-y-start - source-row)> and the analogous
      C<x>. C<dest-y>/C<dest-x> are the visible-viewport offsets the
      caller already computed.

    The output dims have the invariant that
    B<lenx = blit-cols × cell-px-x> and B<leny = blit-rows × cell-px-y>,
    which is what makes C<NCSCALE_STRETCH> render the source crop into
    the dest plane at exactly 1:1 — no scale_visual call, no aspect
    drift. Width-invariance across vertical scroll positions follows
    from the fact that C<blit-cols> and C<lenx> only depend on
    C<self-cols>, C<rcellx>, C<source-col> and C<cols> — never on
    C<source-row> or C<rows>.

    Exported so the test suite can exercise the math without spinning
    up notcurses. )
sub compute-clip-only-blit(
    UInt :$self-rows!,  UInt :$self-cols!,
    UInt :$cell-px-y!,  UInt :$cell-px-x!,
    UInt :$rcelly!,     UInt :$rcellx!,
    Int  :$dest-y!,     Int  :$dest-x!,
    Int  :$source-row!, Int  :$source-col!,
    UInt :$rows!,       UInt :$cols!,
    --> Hash
) is export {
    # If the image is too tall/wide for its own widget, clip its cell
    # footprint to the widget's. This matches !emit-blit's `min self.rows`.
    my Int $img-cell-rows = ($rcelly min $self-rows).Int;
    my Int $img-cell-cols = ($rcellx min $self-cols).Int;
    return {} if $img-cell-rows <= 0 || $img-cell-cols <= 0;

    # Where the image sits inside the widget cell grid (centered).
    my Int $img-top-cell  = (($self-rows - $img-cell-rows) div 2).Int;
    my Int $img-left-cell = (($self-cols - $img-cell-cols) div 2).Int;

    # Image cell range in widget cell coords.
    my Int $img-cell-y-end = $img-top-cell  + $img-cell-rows;
    my Int $img-cell-x-end = $img-left-cell + $img-cell-cols;

    # Visible widget cell range, intersected with image cell range.
    my Int $vis-cell-y-start = $img-top-cell  max $source-row;
    my Int $vis-cell-y-end   = $img-cell-y-end min ($source-row + $rows.Int);
    my Int $vis-cell-x-start = $img-left-cell max $source-col;
    my Int $vis-cell-x-end   = $img-cell-x-end min ($source-col + $cols.Int);

    # No overlap — image isn't in the visible window.
    return {} if $vis-cell-y-end <= $vis-cell-y-start
              || $vis-cell-x-end <= $vis-cell-x-start;

    # Convert to image-local cell coords (which row/col of the image
    # itself is the first visible one + how many are visible).
    my Int $img-row-start = $vis-cell-y-start - $img-top-cell;
    my Int $img-row-count = $vis-cell-y-end   - $vis-cell-y-start;
    my Int $img-col-start = $vis-cell-x-start - $img-left-cell;
    my Int $img-col-count = $vis-cell-x-end   - $vis-cell-x-start;

    # Source pixel crop. With the visual pre-scaled to cell-aligned
    # natural dims, every image cell row is exactly cell-px-y source
    # pixels tall (and similarly for cols).
    my UInt $begy = ($img-row-start * $cell-px-y).UInt;
    my UInt $leny = ($img-row-count * $cell-px-y).UInt;
    my UInt $begx = ($img-col-start * $cell-px-x).UInt;
    my UInt $lenx = ($img-col-count * $cell-px-x).UInt;

    # Dest plane position within $parent-plane (the caller already
    # computed the visible viewport's dest-y / dest-x — we offset from
    # there by however many widget cells separate the visible top from
    # the image's first visible cell).
    my Int $blit-dest-y = $dest-y + ($vis-cell-y-start - $source-row);
    my Int $blit-dest-x = $dest-x + ($vis-cell-x-start - $source-col);

    {
        begy        => $begy,
        begx        => $begx,
        leny        => $leny,
        lenx        => $lenx,
        blit-rows   => $img-row-count.UInt,
        blit-cols   => $img-col-count.UInt,
        blit-dest-y => $blit-dest-y,
        blit-dest-x => $blit-dest-x,
    };
}
