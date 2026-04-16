use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::ScatterPlot;
use Selkie::Sizing;

# Deterministic point cluster (no rand, so the snapshot is stable
# across runs). Points use the Pair form (x => y) so Raku list
# flattening doesn't split each point into two scalars.
my @points;
for ^7 -> $r {
    for ^7 -> $c {
        # A diagonal stripe through a 0..100 range, plus some scatter
        my $x = ($r + $c) * 7;
        my $y = abs($r - $c) * 12 + 20;
        @points.push: $x => $y;
    }
}

my $sp = Selkie::Widget::ScatterPlot.new(
    series => [{ label => 'cluster', points => @points }],
    x-min  => 0, x-max => 100,
    y-min  => 0, y-max => 100,
    sizing => Sizing.flex,
);

print render-to-string($sp, rows => 8, cols => 30);
