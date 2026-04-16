use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Sparkline;
use Selkie::Sizing;

# Eight rising samples — should render as ▁▂▃▄▅▆▇█
my $s = Selkie::Widget::Sparkline.new(
    data   => [1, 2, 3, 4, 5, 6, 7, 8],
    sizing => Sizing.fixed(1),
);

print render-to-string($s, rows => 1, cols => 8);
