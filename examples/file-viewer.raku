#!/usr/bin/env raku
#
# file-viewer.raku — Browse files in a Split pane with live preview.
#
# Demonstrates:
#   - Selkie::Layout::Split (vertical orientation: top/bottom panes)
#   - FileBrowser modal with extension filtering
#   - Image widget (for .png/.jpg previews)
#   - ScrollView + Text for long text files
#   - Callback subscription: when `current-path` changes, load the content
#     into the appropriate widget and swap the viewer child
#
# Run with:  raku -I lib examples/file-viewer.raku
#
# (Open any text, png, or jpg file — try examples/ itself.)

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Layout::Split;
use Selkie::Widget::Text;
use Selkie::Widget::Border;
use Selkie::Widget::Button;
use Selkie::Widget::Image;
use Selkie::Widget::ScrollView;
use Selkie::Widget::FileBrowser;
use Selkie::Sizing;
use Selkie::Style;

my $app = Selkie::App.new;

# --- Store handlers -------------------------------------------------------

$app.store.register-handler('app/init', -> $st, %ev {
    (db => {
        current-path => Str,
        kind         => 'none',   # 'text' | 'image' | 'none' | 'error'
        text         => '',
        error        => '',
    },);
});

$app.store.register-handler('file/open', -> $st, %ev {
    my $path = %ev<path>;
    my $ext  = $path.IO.extension.lc;
    if $ext eq 'png' | 'jpg' | 'jpeg' | 'gif' | 'bmp' {
        (db => {
            current-path => $path,
            kind         => 'image',
            text         => '',
            error        => '',
        },);
    } else {
        my $content = try { $path.IO.slurp };
        if $content.defined {
            (db => {
                current-path => $path,
                kind         => 'text',
                text         => $content,
                error        => '',
            },);
        } else {
            (db => {
                current-path => $path,
                kind         => 'error',
                text         => '',
                error        => "Could not read $path",
            },);
        }
    }
});

# --- Widget tree ----------------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

# Title
$root.add: Selkie::Widget::Text.new(
    text   => '  File Viewer  —  o: open, Ctrl+Q: quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Split: top pane shows the current path, bottom pane the preview.
my $split = Selkie::Layout::Split.new(
    orientation => 'vertical',   # top | bottom
    ratio       => 0.15,
    sizing      => Sizing.flex,
);
$root.add($split);

# Top pane: current path + action button
my $top = Selkie::Layout::VBox.new(sizing => Sizing.flex);
my $path-text = Selkie::Widget::Text.new(
    text   => '  (no file — press o to open)',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x888888, italic => True),
);
$top.add($path-text);
my $open-btn = Selkie::Widget::Button.new(label => 'Open file...', sizing => Sizing.fixed(1));
$top.add($open-btn);
my $top-border = Selkie::Widget::Border.new(title => 'Current', sizing => Sizing.flex);
$top-border.set-content($top);
$split.set-first($top-border);

# Bottom pane: preview area.
#
# All four possible preview widgets (image, text, error, empty) are
# children of a single VBox. We toggle which one is visible by switching
# its sizing to flex while shrinking the others to fixed(0). This avoids
# Border.set-content (which destroys the previous content) and lets each
# widget retain its plane and state across kind switches.
my $preview-stack = Selkie::Layout::VBox.new(sizing => Sizing.flex);

my $img-widget    = Selkie::Widget::Image.new(sizing => Sizing.fixed(0));
my $text-scroll   = Selkie::Widget::ScrollView.new(sizing => Sizing.fixed(0));
my $text-body     = Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);
$text-scroll.add($text-body);
my $error-widget  = Selkie::Widget::Text.new(
    text   => '',
    sizing => Sizing.fixed(0),
    style  => Selkie::Style.new(fg => 0xFF5555, bold => True),
);
my $empty-widget  = Selkie::Widget::Text.new(
    text   => '  No file loaded.',
    sizing => Sizing.flex,    # initially visible
    style  => Selkie::Style.new(fg => 0x666666, italic => True),
);

$preview-stack.add($img-widget);
$preview-stack.add($text-scroll);
$preview-stack.add($error-widget);
$preview-stack.add($empty-widget);

my $preview-border = Selkie::Widget::Border.new(title => 'Preview', sizing => Sizing.flex);
$preview-border.set-content($preview-stack);
$split.set-second($preview-border);

# Show only one widget in the stack — others get fixed(0) which removes
# them from layout entirely.
sub show-preview(Selkie::Widget $active) {
    for $img-widget, $text-scroll, $error-widget, $empty-widget -> $w {
        $w.update-sizing($w === $active ?? Sizing.flex !! Sizing.fixed(0));
    }
    $preview-stack.mark-dirty;
}

# --- FileBrowser modal ---------------------------------------------------

sub open-picker() {
    my $browser = Selkie::Widget::FileBrowser.new;
    my $modal = $browser.build(
        extensions    => <txt md rakudoc raku rakumod rakutest json png jpg jpeg gif>,
        show-dotfiles => False,
        width-ratio   => 0.7,
        height-ratio  => 0.7,
    );

    $browser.on-select.tap: -> Str $path {
        $app.close-modal;
        $app.store.dispatch('file/open', :$path);
    };

    $app.show-modal($modal);
    $app.focus($browser.focusable-widget);
}

$open-btn.on-press.tap: -> $ { open-picker };

# --- Subscriptions --------------------------------------------------------

# Header shows the current path
$app.store.subscribe-with-callback(
    'header',
    -> $s { $s.get-in('current-path') // '' },
    -> $path {
        if $path.chars > 0 {
            $path-text.set-text("  $path");
        } else {
            $path-text.set-text('  (no file — press o to open)');
        }
    },
    $path-text,
);

# Swap the Border's content based on `kind`. Image/Text widgets are
# persistent — we just update their data and reparent them.
$app.store.subscribe-with-callback(
    'preview',
    -> $s {
        # Fingerprint covers kind + path + text length so any meaningful
        # change re-fires.
        "{$s.get-in('kind') // 'none'}|{$s.get-in('current-path') // ''}|{($s.get-in('text') // '').chars}"
    },
    -> $_ {
        my $kind  = $app.store.get-in('kind') // 'none';
        my $path  = $app.store.get-in('current-path');
        my $text  = $app.store.get-in('text') // '';
        my $error = $app.store.get-in('error') // '';

        given $kind {
            when 'image' {
                $img-widget.set-file($path);
                show-preview($img-widget);
            }
            when 'text' {
                $text-body.set-text($text);
                show-preview($text-scroll);
                $text-scroll.scroll-to-start;
                $app.focus($text-scroll);
            }
            when 'error' {
                $error-widget.set-text("  $error");
                show-preview($error-widget);
            }
            default {
                show-preview($empty-widget);
            }
        }
    },
    $preview-border,
);

# --- Global keybinds -----------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.on-key('o',      -> $ { open-picker });

# --- Go ------------------------------------------------------------------

$app.store.dispatch('app/init');
$app.store.tick;

$app.focus($open-btn);
$app.run;
