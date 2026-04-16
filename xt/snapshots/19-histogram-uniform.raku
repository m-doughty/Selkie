use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Histogram;
use Selkie::Sizing;

# 100 evenly-distributed samples in [0, 100), 10 equal-width bins.
# Each bin should hold exactly 10 samples → identical bar heights.
my @samples = (0..99).map: *.Real;

my $h = Selkie::Widget::Histogram.new(
    values => @samples,
    bins   => 10,
    sizing => Sizing.flex,
);

print render-to-string($h, rows => 12, cols => 60);
