use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Heatmap;
use Selkie::Sizing;

# 4×4 checkerboard pattern. The plain snapshot would show only ████
# everywhere (one full block per cell) with no information; the
# styled snapshot reveals the alternating viridis stops.
my $h = Selkie::Widget::Heatmap.new(
    data => [
        [0, 1, 0, 1],
        [1, 0, 1, 0],
        [0, 1, 0, 1],
        [1, 0, 1, 0],
    ],
    sizing => Sizing.fixed(4),
);

print render-to-string($h, rows => 4, cols => 4, :capture-styles);
