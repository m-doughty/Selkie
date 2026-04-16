use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Axis;
use Selkie::Sizing;

my $axis = Selkie::Widget::Axis.new(
    edge       => 'left',
    min        => 0,
    max        => 1.0,
    tick-count => 5,
    sizing     => Sizing.flex,
);

# Reserve enough cols for the widest label + axis line
print render-to-string($axis, rows => 12, cols => 5);
