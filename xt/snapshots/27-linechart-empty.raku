use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::LineChart;
use Selkie::Sizing;

# Startup state for a monitoring widget — no samples yet. Should
# render a centered "No data" message rather than crash or blank out.
my $chart = Selkie::Widget::LineChart.new(
    series => [{ label => 'pending', values => [] }],
    y-min  => 0,
    y-max  => 100,
    sizing => Sizing.flex,
);

print render-to-string($chart, rows => 6, cols => 30);
