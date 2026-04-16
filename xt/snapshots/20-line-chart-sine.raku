use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::LineChart;
use Selkie::Sizing;

my @samples = (^60).map: { (sin($_ * 0.1) * 50 + 50).Int };

my $chart = Selkie::Widget::LineChart.new(
    series => [{ label => 'sine', values => @samples }],
    y-min  => 0,
    y-max  => 100,
    sizing => Sizing.flex,
);

print render-to-string($chart, rows => 12, cols => 60);
