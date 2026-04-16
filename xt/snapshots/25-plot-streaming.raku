use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Plot;
use Selkie::Sizing;

# A streaming plot with twenty samples pushed before render. The
# native ncuplot handles the actual glyph selection (braille); our
# job is to verify the lifecycle (handle creation on first render,
# buffered samples flushed correctly, render produces non-empty
# output).
my $plot = Selkie::Widget::Plot.new(
    type   => 'uint',
    min-y  => 0,
    max-y  => 100,
    sizing => Sizing.flex,
);

# Push a sine-like wave: 20 samples climbing then falling.
my @samples = (10, 25, 40, 55, 70, 85, 95, 100, 95, 85,
               70, 55, 40, 25, 10, 5, 0, 5, 15, 30);
for @samples.kv -> $i, $y {
    $plot.push-sample($i, $y);
}

print render-to-string($plot, rows => 8, cols => 40);
