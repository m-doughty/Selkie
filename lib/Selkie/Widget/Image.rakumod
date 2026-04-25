=begin pod

=head1 NAME

Selkie::Widget::Image - Display an image via notcurses visual system

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Image;
use Selkie::Sizing;

my $img = Selkie::Widget::Image.new(
    file   => 'avatar.png',
    sizing => Sizing.fixed(20),
);

# Change later
$img.set-file('new-avatar.png');
$img.clear-image;

=end code

=head1 DESCRIPTION

Loads and renders an image file onto its plane. If the terminal supports
pixel graphics (Kitty, iTerm2, WezTerm, Ghostty, a few others),
full-resolution pixels are rendered. Otherwise notcurses falls back to
Unicode block / quadrant / braille art.

The image is centred in the widget's area and scaled to fit.

=head2 Pixel bleed

B<Notcurses child planes are not clipped to parent bounds.> Pixel images
can spill past the widget's logical rectangle into neighbouring cells.
The usual workaround is to wrap the image in L<Selkie::Widget::Border>,
which redraws its edges after content to cover bleed.

=head2 Sprixel position tracking

Notcurses pixel sprixels don't follow their parent plane when it moves
— the sprixel stays painted at its old terminal coordinates until the
blit-plane is explicitly destroyed. Image detects moves by asking
notcurses for the plane's true absolute position each render (via
C<ncplane_abs_y> / C<ncplane_abs_x>), not by trusting C<Widget.abs-y>
/ C<Widget.abs-x>. This means Image is immune to upstream containers
that forget to propagate C<set-viewport> to their descendants — the
cache invalidates the moment notcurses reports a different position,
regardless of whether any Selkie-level tracking was updated.

=head1 EXAMPLES

=head2 Preview in a Split

=begin code :lang<raku>

my $preview = Selkie::Widget::Image.new(sizing => Sizing.flex);
my $border  = Selkie::Widget::Border.new(title => 'Preview', sizing => Sizing.flex);
$border.set-content($preview);

# When user selects a new file:
$preview.set-file($selected-path);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Border> — wrap to contain pixel bleed

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Visual;
use Notcurses::Native::Plane;
use Notcurses::Native::Context;
use Selkie::Widget;

unit class Selkie::Widget::Image does Selkie::Widget;

has Str $!file;
has NcvisualHandle $!visual;
has Bool $!loaded = False;
has NcplaneHandle $!blit-plane;

# Cache of the last-blitted state so repeated renders with identical
# inputs can skip the destroy + recreate of the sprixel. Without this
# cache, any ancestor cascading dirty through the tree (a sibling
# resizing in a VBox, a scroll event marking a parent CardList dirty,
# etc.) re-blits every visible Image on every frame, and the terminal
# can drop the rapid sprixel-remove/add pairs — visible as sprites
# disappearing or flickering during typing into a multi-line input.
#
# Position is part of the cache key: notcurses sprixels (Kitty / Sixel
# pixel data) don't automatically follow their parent plane when it's
# repositioned — the sprixel stays painted at its old terminal
# coordinates until the blit-plane is destroyed. So any move (same
# dims, new abs-y / abs-x) has to invalidate too; otherwise ghost
# sprixels bleed into whatever widget is now at the old position.
#
# Position is read from C<ncplane_abs_y> / C<ncplane_abs_x> (the
# notcurses plane's stored absolute coordinates), not from
# C<Widget.abs-y> / C<Widget.abs-x>. Widget-level abs-y only updates
# when a parent calls C<set-viewport>, and several Selkie containers
# (Modal, ScrollView, and historically CardList) failed to cascade
# that through subtrees — which would leave the Image cache with
# stale abs-y, skip the re-blit, and leave a ghost sprixel at the old
# position. Reading from notcurses makes Image's move-detection
# independent of Selkie's set-viewport hygiene: the value is the same
# C struct field notcurses uses to composite the sprixel, and it
# updates immediately whenever any ancestor plane is repositioned.
has UInt $!last-rows = 0;
has UInt $!last-cols = 0;
has Int  $!last-abs-y = Int;
has Int  $!last-abs-x = Int;
has Str  $!last-file;

#| Height in rows. Same as C<self.rows>; provided for the ScrollView
#| contract.
method logical-height(--> UInt) { self.rows }

#|( Eagerly destroy the blit-plane on a real resize. The blit-plane is
    a child of C<self.plane>, sized to the scaled image dimensions —
    when the parent shrinks (e.g. the host card is bottom-clipped by
    CardList), notcurses doesn't auto-clip or auto-destroy the child,
    so a stale sprixel can extend beyond the Image's new bounds and
    paint into whatever sits below. C<render> would clean up the same
    blit-plane on its next cache miss, but tearing it down here makes
    the cleanup atomic with the resize itself, ruling out any window
    where the larger blit-plane lingers. )
method handle-resize(UInt $rows, UInt $cols) {
    my $changed = $rows != self.rows || $cols != self.cols;
    return unless $changed;
    self.resize($rows, $cols);
    self!destroy-blit-plane;
}

#| The currently displayed file path, or C<Nil>.
method file(--> Str) { $!file }

#|( True when the blit-plane cache has an active, non-invalidated
    entry from a previous successful blit. Intended for tests that
    assert cache invalidation semantics without needing a live
    notcurses plane — callers shouldn't depend on this in production
    rendering logic (C<render> handles cache decisions itself). )
method blit-cache-valid(--> Bool) {
    $!last-rows > 0 && $!last-cols > 0 && $!last-file.defined;
}

#|( Test-only hook: seed the cache with arbitrary values so tests can
    verify invalidation paths without running C<render> (which needs
    a live notcurses plane). Production code populates these fields
    only from inside C<render> on a successful blit. )
method populate-blit-cache-for-test(
    UInt :$rows!, UInt :$cols!, Int :$abs-y = 0, Int :$abs-x = 0, Str :$file!
) {
    $!last-rows  = $rows;
    $!last-cols  = $cols;
    $!last-abs-y = $abs-y;
    $!last-abs-x = $abs-x;
    $!last-file  = $file;
}

#|( Swap the displayed image. No-op if the same path is already loaded.
    Triggers a re-blit on the next render. )
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
}

method !unload() {
    if $!visual {
        ncvisual_destroy($!visual);
        $!visual = NcvisualHandle;
    }
    $!loaded = False;
}

method !destroy-blit-plane() {
    if $!blit-plane {
        ncplane_destroy($!blit-plane);
        $!blit-plane = NcplaneHandle;
    }
    # Invalidate the cache so the next render re-blits. Callers that
    # destroy the blit-plane (render itself, park, set-file) always
    # want a fresh blit on the following frame.
    $!last-rows  = 0;
    $!last-cols  = 0;
    $!last-abs-y = Int;
    $!last-abs-x = Int;
    $!last-file  = Str;
}

method render() {
    return without self.plane;

    # Fast path: nothing about the blit changed since last render, so
    # keep the existing sprixel in place. Position is part of the key
    # — sprixels don't follow plane moves, so same-dims-new-position
    # still needs a re-blit to avoid ghosting. We ask notcurses for
    # the plane's current absolute position rather than reading
    # C<self.abs-y> / C<self.abs-x>; see the attribute comment above.
    my UInt $rows  = self.rows;
    my UInt $cols  = self.cols;
    my Int  $abs-y = ncplane_abs_y(self.plane);
    my Int  $abs-x = ncplane_abs_x(self.plane);
    my Str  $file  = $!file;
    if $!blit-plane.defined
       && $rows == $!last-rows
       && $cols == $!last-cols
       && $!last-abs-y.defined && $abs-y == $!last-abs-y
       && $!last-abs-x.defined && $abs-x == $!last-abs-x
       && ($file // '') eq ($!last-file // '') {
        self.clear-dirty;
        return;
    }

    ncplane_resize_simple(self.plane, $rows, $cols);
    ncplane_erase(self.plane);
    self!destroy-blit-plane;

    self!load;
    unless $!loaded {
        my $style = self.theme.text-dim;
        self.apply-style($style);
        my $msg = $file.defined ?? "Cannot load: {$file.IO.basename}" !! "No image";
        ncplane_putstr_yx(self.plane, $rows div 2, 1, $msg);
        self.clear-dirty;
        return;
    }

    my $nc = self!notcurses-handle;

    my $pixel-ok = notcurses_check_pixel_support($nc);
    my $blitter = $pixel-ok > 0 ?? NCBLIT_PIXEL
                                !! ncvisual_media_defblitter($nc, NCSCALE_SCALE);

    my $geom = Ncvgeom.new;
    my $probe = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
    $probe.set-plane(self.plane);
    ncvisual_geom($nc, $!visual, $probe, $geom);

    my UInt $img-rows = $geom.rcelly;
    my UInt $img-cols = $geom.rcellx;
    my UInt $offset-y = ($img-rows < self.rows) ?? (self.rows - $img-rows) div 2 !! 0;
    my UInt $offset-x = ($img-cols < self.cols) ?? (self.cols - $img-cols) div 2 !! 0;

    my $opts = NcplaneOptions.new(
        y => $offset-y, x => $offset-x,
        rows => $img-rows max 1, cols => $img-cols max 1,
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

    # Record the state we just blitted so the next render can skip the
    # destroy + re-blit if nothing has changed since. Only reached on
    # a successful blit path (the early returns above leave the cache
    # invalid, which !destroy-blit-plane already handles).
    $!last-rows  = $rows;
    $!last-cols  = $cols;
    $!last-abs-y = $abs-y;
    $!last-abs-x = $abs-x;
    $!last-file  = $file;

    self.clear-dirty;
}

method !notcurses-handle(--> NotcursesHandle) {
    ncplane_notcurses(self.plane);
}

method destroy() {
    self!destroy-blit-plane;
    self!unload;
    self!destroy-plane;
}

#|( When an Image is parked off-screen by a container swap (e.g. tab
    switch in CharacterEditor), the parent plane moves but the
    sprixel — Sixel/Kitty pixel data the terminal renders at an
    absolute screen position — is NOT cleared by notcurses just
    because its plane moved. Destroy the blit-plane so the next
    notcurses_render flushes the sprixel removal to the terminal.
    The blit-plane gets recreated when render fires again on
    re-install. )
method park() {
    self!destroy-blit-plane;
    self.reposition(10_000, 0) if self.plane;
}
