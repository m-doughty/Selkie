use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Border;
use Selkie::Sizing;

# A Border with a title and no content — smallest reasonable regression
# test for title-rendering and box-drawing characters. Many layout bugs
# manifest as off-by-one on the frame corners or missing title text.

my $border = Selkie::Widget::Border.new(
    title  => 'Settings',
    sizing => Sizing.flex,
);

print render-to-string($border, rows => 4, cols => 24);
