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

method logical-height(--> UInt) { self.rows }

method file(--> Str) { $!file }

method set-file(Str $path) {
    return if $path eq ($!file // '');
    self!unload;
    $!file = $path;
    self.mark-dirty;
}

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

    # Choose blitter: pixel first, then best available
    my $pixel-ok = notcurses_check_pixel_support($nc);
    my $blitter = $pixel-ok > 0 ?? NCBLIT_PIXEL
                                !! ncvisual_media_defblitter($nc, NCSCALE_SCALE);

    # Query rendered geometry to calculate centering offset
    my $geom = Ncvgeom.new;
    my $probe = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
    $probe.set-plane(self.plane);
    ncvisual_geom($nc, $!visual, $probe, $geom);

    my UInt $img-rows = $geom.rcelly;
    my UInt $img-cols = $geom.rcellx;
    my UInt $offset-y = ($img-rows < self.rows) ?? (self.rows - $img-rows) div 2 !! 0;
    my UInt $offset-x = ($img-cols < self.cols) ?? (self.cols - $img-cols) div 2 !! 0;

    # Create a child plane at the centered position for the blit
    my $opts = NcplaneOptions.new(
        y => $offset-y, x => $offset-x,
        rows => $img-rows max 1, cols => $img-cols max 1,
    );
    $!blit-plane = ncplane_create(self.plane, $opts);

    my $vopts = NcvisualOptions.new(scaling => NCSCALE_SCALE, :$blitter);
    $vopts.set-plane($!blit-plane);

    my $result = ncvisual_blit($nc, $!visual, $vopts);

    # Fall back if pixel blit failed
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
