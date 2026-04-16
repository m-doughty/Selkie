use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::LineChart;
use Selkie::Sizing;

# Verifies series colours appear in the rendered cells. Without
# styled snapshots, multi-series tests can't assert which line is
# which.
my @sine   = (^20).map: { (sin($_ * 0.4) * 30 + 50).Int };
my @cosine = (^20).map: { (cos($_ * 0.4) * 30 + 50).Int };

my $chart = Selkie::Widget::LineChart.new(
    series => [
        { label => 'sin', values => @sine,   color => 0x4477AA },
        { label => 'cos', values => @cosine, color => 0xEE6677 },
    ],
    y-min  => 0,
    y-max  => 100,
    sizing => Sizing.flex,
);

print render-to-string($chart, rows => 8, cols => 30, :capture-styles);
