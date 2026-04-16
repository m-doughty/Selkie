use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Legend;
use Selkie::Sizing;

# Styled snapshot — verifies that the per-series color reaches the
# rendered cell. Without :capture-styles all three rows would look
# identical (same swatch glyph + same label text differences only).
my $legend = Selkie::Widget::Legend.new(
    series => [
        { label => 'cpu',     color => 0xE69F00 },
        { label => 'memory',  color => 0x56B4E9 },
        { label => 'iowait',  color => 0x009E73 },
    ],
    orientation => 'vertical',
    sizing      => Sizing.fixed(3),
);

print render-to-string($legend, rows => 3, cols => 12, :capture-styles);
