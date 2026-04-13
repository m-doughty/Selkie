use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Layout::HBox;
use Selkie::Sizing;

my $root = Selkie::Layout::HBox.new(sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(text => 'left',  sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(text => 'right', sizing => Sizing.flex);

print render-to-string($root, rows => 1, cols => 20);
