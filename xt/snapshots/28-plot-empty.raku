use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Plot;
use Selkie::Sizing;

# Startup state for a streaming Plot — native ncuplot handle isn't
# even created until the first sample arrives. Should show "No data".
my $plot = Selkie::Widget::Plot.new(
    type   => 'uint',
    min-y  => 0,
    max-y  => 100,
    sizing => Sizing.flex,
);

print render-to-string($plot, rows => 6, cols => 30);
