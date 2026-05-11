use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::Text;
use Selkie::Sizing;

# A selected card taller than the viewport must always render — the
# user picked it, so hiding it would be worse than partially drawing
# it. Here display-h=5 falls below the card's own min-display-height=7,
# but the selected-exempt clause keeps it on screen anyway. Both
# borders end up hidden (the card is clipped on both sides); a
# wrapped scrollable content widget takes responsibility for showing
# the right portion in real chat usage.
my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

my $text   = Selkie::Widget::Text.new(text => 'tall card', sizing => Sizing.flex);
my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
$border.set-content($text);
$cards.add-item($text, root => $border, height => 20, :$border,
                min-display-height => 7);

$cards.select-index(0);

print render-to-string($cards, rows => 5, cols => 20);
