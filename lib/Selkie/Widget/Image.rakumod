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

#| Height in rows. Same as C<self.rows>; provided for the ScrollView
#| contract.
method logical-height(--> UInt) { self.rows }

#| The currently displayed file path, or C<Nil>.
method file(--> Str) { $!file }

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
}

method render() {
    return without self.plane;

    ncplane_resize_simple(self.plane, self.rows, self.cols);
    ncplane_erase(self.plane);
    self!destroy-blit-plane;

    self!load;
    unless $!loaded {
        my $style = self.theme.text-dim;
        self.apply-style($style);
        my $msg = $!file.defined ?? "Cannot load: {$!file.IO.basename}" !! "No image";
        ncplane_putstr_yx(self.plane, self.rows div 2, 1, $msg);
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
