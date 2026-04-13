use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Layout::VBox;
use Selkie::Sizing;

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(text => 'first row', sizing => Sizing.fixed(1));
$root.add: Selkie::Widget::Text.new(text => 'second row', sizing => Sizing.fixed(1));

print render-to-string($root, rows => 3, cols => 20);
