use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::LineChart;
use Selkie::Sizing;

my @samples = (^30).map: { (sin($_ * 0.3) * 30 + 50).Int };

my $chart = Selkie::Widget::LineChart.new(
    series     => [{ label => 'load', values => @samples }],
    y-min      => 0,
    y-max      => 100,
    fill-below => True,
    sizing     => Sizing.flex,
);

print render-to-string($chart, rows => 10, cols => 50);
