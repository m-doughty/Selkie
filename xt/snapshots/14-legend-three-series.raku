use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Legend;
use Selkie::Sizing;

my $legend = Selkie::Widget::Legend.new(
    series => [
        { label => 'cpu',     color => 0xE69F00 },
        { label => 'memory',  color => 0x56B4E9 },
        { label => 'iowait',  color => 0x009E73 },
    ],
    orientation => 'vertical',
    sizing      => Sizing.fixed(3),
);

print render-to-string($legend, rows => 3, cols => 12);
