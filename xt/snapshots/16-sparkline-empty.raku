use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Sparkline;
use Selkie::Sizing;

# Empty data — should render a blank cell, no crash
my $s = Selkie::Widget::Sparkline.new(
    data   => [],
    sizing => Sizing.fixed(1),
);

print render-to-string($s, rows => 1, cols => 10);
