use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::BarChart;
use Selkie::Sizing;

my $chart = Selkie::Widget::BarChart.new(
    data => [
        { label => 'apples',   value => 12 },
        { label => 'pears',    value =>  7 },
        { label => 'cherries', value => 15 },
        { label => 'plums',    value =>  4 },
    ],
    orientation => 'horizontal',
    sizing      => Sizing.flex,
);

print render-to-string($chart, rows => 10, cols => 40);
