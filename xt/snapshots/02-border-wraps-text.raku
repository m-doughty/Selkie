use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Widget::Border;
use Selkie::Sizing;

# The canonical MoarVM-spesh trigger pattern: Border wrapping a leaf
# widget, rendered through shared notcurses + ncplane_at_yx readback.
# One render in one process should never trip the bug.

my $text = Selkie::Widget::Text.new(
    text   => 'inside',
    sizing => Sizing.flex,
);

my $border = Selkie::Widget::Border.new(
    title  => 'Box',
    sizing => Sizing.flex,
);
$border.set-content($text);

print render-to-string($border, rows => 5, cols => 20);
