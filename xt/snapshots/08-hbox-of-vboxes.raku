use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Layout::HBox;
use Selkie::Layout::VBox;
use Selkie::Sizing;

# HBox splitting horizontally, each half holds a VBox with two Texts.
# Exercises nested container layout allocation.

my $left = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$left.add: Selkie::Widget::Text.new(text => 'L1', sizing => Sizing.fixed(1));
$left.add: Selkie::Widget::Text.new(text => 'L2', sizing => Sizing.fixed(1));

my $right = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$right.add: Selkie::Widget::Text.new(text => 'R1', sizing => Sizing.fixed(1));
$right.add: Selkie::Widget::Text.new(text => 'R2', sizing => Sizing.fixed(1));

my $root = Selkie::Layout::HBox.new(sizing => Sizing.flex);
$root.add($left);
$root.add($right);

print render-to-string($root, rows => 3, cols => 20);
