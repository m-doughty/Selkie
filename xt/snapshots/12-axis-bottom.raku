use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Axis;
use Selkie::Sizing;

my $axis = Selkie::Widget::Axis.new(
    edge       => 'bottom',
    min        => 0,
    max        => 100,
    tick-count => 5,
    sizing     => Sizing.fixed(2),
);

print render-to-string($axis, rows => 2, cols => 60);
