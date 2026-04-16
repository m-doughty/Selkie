use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::BarChart;
use Selkie::Sizing;

my $chart = Selkie::Widget::BarChart.new(
    data => [
        { label => 'Q1', value => 50  },
        { label => 'Q2', value => 80  },
        { label => 'Q3', value => 65  },
        { label => 'Q4', value => 100 },
    ],
    sizing => Sizing.flex,
);

print render-to-string($chart, rows => 12, cols => 40);
