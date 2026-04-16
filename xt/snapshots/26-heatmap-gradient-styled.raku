use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Heatmap;
use Selkie::Sizing;

# A linear gradient across the columns. Each column should pick up
# successive stops of the viridis ramp; the styled snapshot verifies
# the per-cell colour assignment.
my @grid = (^4).map: { (^9).map({ $_ / 8 }).list };

my $h = Selkie::Widget::Heatmap.new(
    data   => @grid,
    sizing => Sizing.flex,
);

print render-to-string($h, rows => 4, cols => 9, :capture-styles);
