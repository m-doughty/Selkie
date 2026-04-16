use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::LineChart;
use Selkie::Sizing;

# Two crossing series — sine and cosine. Lines intersect; verifies
# multi-series rendering and crossing handling.
my @sine   = (^40).map: { (sin($_ * 0.2) * 40 + 50).Int };
my @cosine = (^40).map: { (cos($_ * 0.2) * 40 + 50).Int };

my $chart = Selkie::Widget::LineChart.new(
    series => [
        { label => 'sin', values => @sine,   color => 0x4477AA },
        { label => 'cos', values => @cosine, color => 0xEE6677 },
    ],
    y-min  => 0,
    y-max  => 100,
    sizing => Sizing.flex,
);

print render-to-string($chart, rows => 10, cols => 60);
