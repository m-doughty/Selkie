use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Widget::Border;
use Selkie::Layout::VBox;
use Selkie::Sizing;

# Deep nesting: Border → VBox → two Texts. Exercises parent-plane
# resize + child layout allocation through multiple levels.

my $inner = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$inner.add: Selkie::Widget::Text.new(text => 'top',    sizing => Sizing.fixed(1));
$inner.add: Selkie::Widget::Text.new(text => 'bottom', sizing => Sizing.fixed(1));

my $border = Selkie::Widget::Border.new(title => 'Nested', sizing => Sizing.flex);
$border.set-content($inner);

print render-to-string($border, rows => 5, cols => 22);
