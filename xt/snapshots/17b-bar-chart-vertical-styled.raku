use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::BarChart;
use Selkie::Sizing;

# Verifies that each bar gets a distinct color from the palette. The
# plain snapshot would show only the glyphs, hiding any palette
# regressions.
my $chart = Selkie::Widget::BarChart.new(
    data => [
        { label => 'Q1', value => 50  },
        { label => 'Q2', value => 80  },
        { label => 'Q3', value => 65  },
        { label => 'Q4', value => 100 },
    ],
    sizing => Sizing.flex,
);

print render-to-string($chart, rows => 12, cols => 40, :capture-styles);
