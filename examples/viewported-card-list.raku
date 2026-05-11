#!/usr/bin/env raku
#
# viewported-card-list.raku — Row-scrolled cards, including Image children.
#
# Demonstrates:
#   - ViewportedCardList for row-by-row scrolling through tall content
#   - Card selection (Up/Down) staying separate from row scrolling
#     (PgUp/PgDown, mouse wheel)
#   - Image cards as siblings in a stack of varied-height cards, scrolling
#     past the viewport edge
#   - Mixed layouts inside cards: pure text, image-only, image+caption HBox
#
# Run with:  raku -I lib examples/viewported-card-list.raku
#
# Image source priority:
#   1. SELKIE_DEMO_IMAGES=/path/a.png:/path/b.png …   (colon-separated list)
#   2. The notcurses sample-data directory bundled in this monorepo at
#      ../Notcurses-Native/vendor/notcurses/data/ — picks a handful of
#      real photos / illustrations.
#   3. A 1x1 PNG written to $TMPDIR as a placeholder, so the example still
#      runs on a clean Selkie install with no images available.

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::ViewportedCardList;
use Selkie::Widget::Border;
use Selkie::Widget::Image;
use Selkie::Widget::Text;
use Selkie::Sizing;
use Selkie::Style;

sub base64-decode(Str $src --> Blob) {
    my @alphabet = flat 'A'..'Z', 'a'..'z', '0'..'9', '+', '/';
    my %value;
    for @alphabet.kv -> $idx, $ch {
        %value{$ch} = $idx;
    }
    my @bytes;
    my Int $buffer = 0;
    my Int $bits = 0;

    for $src.comb.grep({ %value{$_}:exists }) -> $ch {
        $buffer = ($buffer +< 6) + %value{$ch};
        $bits += 6;
        while $bits >= 8 {
            $bits -= 8;
            @bytes.push(($buffer +> $bits) +& 0xff);
        }
    }

    Blob.new(@bytes);
}

sub placeholder-image-path(--> Str) {
    my $path = $*TMPDIR.add('selkie-viewported-card-list-demo.png');
    unless $path.e {
        my $png = base64-decode(q:to/PNG/.trim);
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
PNG
        spurt $path, $png;
    }
    $path.Str;
}

sub demo-image-paths(--> List) {
    # Honour an explicit override first.
    with %*ENV<SELKIE_DEMO_IMAGES> {
        my @paths = .split(':').grep({ .IO.f });
        return @paths.List if @paths;
    }

    # Try the notcurses sample-data dir bundled with this monorepo.
    # The example lives at Selkie/examples/, so the sibling Notcurses-Native
    # checkout is two directories up.
    my $here = $?FILE.IO.parent.absolute;
    my @candidates = <
        atma.png
        chunli01.png
        spaceship.png
        eagles.png
        worldmap.png
        natasha-blur.png
        changes.jpg
        notcurses.png
        fonts.jpg
        aidsrobots.jpeg
    >.map: -> $name {
        $here.IO.parent.parent.add('Notcurses-Native/vendor/notcurses/data').add($name).absolute;
    };
    my @existing = @candidates.grep({ .IO.f });
    return @existing.List if @existing;

    # Last resort: a single tiny placeholder.
    (placeholder-image-path(),).List;
}

my $app = Selkie::App.new;
my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

$root.add: Selkie::Widget::Text.new(
    text   => '  Up/Down select · Shift+Up/Down row scroll · PgUp/PgDown page scroll · wheel scroll · Home/End jump · Ctrl+Q quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

my $cards = Selkie::Widget::ViewportedCardList.new(
    sizing        => Sizing.flex,
    follow-bottom => False,
);
my $cards-border = Selkie::Widget::Border.new(title => 'Cards', sizing => Sizing.flex);
$cards-border.set-content($cards);
$root.add($cards-border);

sub add-text-card(Str $title, Str $body, UInt $height = 5) {
    my $box = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $box.add: Selkie::Widget::Text.new(
        text   => $title,
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x9ECE6A, bold => True),
    );
    $box.add: Selkie::Widget::Text.new(
        text   => $body,
        sizing => Sizing.flex,
        style  => Selkie::Style.new(fg => 0xD5D6E0),
    );

    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($box);
    $cards.add-item($box, root => $border, height => $height, :$border);
}

sub add-image-with-caption(Str $image-path, Str $title, Str $caption, UInt :$height = 12) {
    my $row = Selkie::Layout::HBox.new(sizing => Sizing.flex);

    my $image = Selkie::Widget::Image.new(sizing => Sizing.fixed(24), :clip-only);
    $image.set-file($image-path);
    $row.add($image);

    my $copy = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $copy.add: Selkie::Widget::Text.new(
        text   => $title,
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0xF7768E, bold => True),
    );
    $copy.add: Selkie::Widget::Text.new(
        text   => $caption,
        sizing => Sizing.flex,
        style  => Selkie::Style.new(fg => 0xD5D6E0),
    );
    $row.add($copy);

    my $border = Selkie::Widget::Border.new(title => $title, sizing => Sizing.flex);
    $border.set-content($row);
    $cards.add-item($row, root => $border, height => $height, :$border);
}

sub add-image-only(Str $image-path, Str $title, UInt :$height = 14) {
    my $image = Selkie::Widget::Image.new(sizing => Sizing.flex, :clip-only);
    $image.set-file($image-path);
    my $border = Selkie::Widget::Border.new(title => $title, sizing => Sizing.flex);
    $border.set-content($image);
    $cards.add-item($image, root => $border, height => $height, :$border);
}

my @images = demo-image-paths();
# Round-robin index into @images so the layout below stays valid even
# when only a handful of paths resolved (or a single placeholder).
my $img-idx = 0;
sub next-img(--> Str) {
    my $p = @images[$img-idx % @images.elems];
    $img-idx++;
    $p;
}

add-text-card(
    'Opening note',
    'Stack of mixed cards — scroll past the bottom with PgDown or the mouse wheel. Up/Down still walks selection one card at a time even mid-scroll.',
    5,
);

add-image-with-caption(
    next-img(),
    'First image',
    'Caption next to a 24-cell-wide Image. The image gets cropped at the viewport edge when scrolled partially off-screen instead of bleeding past the card border.',
    height => 11,
);

add-text-card(
    'Selection vs scroll',
    'Pressing Down here selects the card below — its border highlights. PgDown moves the row offset by one viewport, which can leave the selected card entirely off-screen until you scroll back or press Down to chase it.',
    8,
);

add-image-only(next-img(), 'Image-only card', height => 16);

add-text-card(
    'Short status',
    'Selkie 0.6 · ViewportedCardList',
    3,
);

add-image-with-caption(
    next-img(),
    'Second image',
    'Mixed-height cards are intentional: row scrolling has to handle non-uniform stride. PgUp goes the other way.',
    height => 10,
);

add-text-card(
    'Mid-list prose',
    'The interior cells are filled in by the base-cell fallback during merge, so the background stays solid as cards scroll under the viewport. Try scrolling the image cards out from the top — their sprixels get re-emitted as the visible slice shrinks.',
    9,
);

add-image-only(next-img(), 'Tall illustration', height => 18);

add-text-card(
    'Bulleted list',
    "  • Up / Down — select a card\n  • Shift+Up / Shift+Down — scroll one row\n  • PgUp / PgDown — scroll one viewport\n  • Mouse wheel — 3-row scroll per tick\n  • Home / End — jump to first / last\n  • Ctrl+Q — quit",
    9,
);

add-image-with-caption(
    next-img(),
    'Third image',
    'Another image+caption to demonstrate that several Image planes coexist in the same scrollable list — each independent, each with its own crop on partial visibility.',
    height => 11,
);

add-text-card(
    'Longer card',
    'Cards can be tall and still respect row scrolling. The selected card always tries to stay at least partially in view as you walk selection up or down; pure row scrolling (PgUp / PgDown / wheel) is independent and can leave any card fully off the visible region.',
    12,
);

add-image-only(next-img(), 'Late image', height => 14);

add-text-card(
    'Epilogue',
    'Home jumps to the first card and resets the scroll to the top; End walks to the last card and pushes scroll to the maximum offset.',
    6,
);

add-text-card(
    'Tail card',
    'You should be able to scroll this one past the bottom edge of the viewport and back up. PgUp returns one viewport at a time.',
    5,
);

$cards.select-first;
$app.focus($cards);

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;
