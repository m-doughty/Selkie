use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::Text;
use Selkie::Sizing;

# Three cards in a viewport too small to fit them all when the middle
# card is selected. Card 0 (h=8) would top-clip to display-h=4, which
# is below its min-display-height=6 and well above the 3-row floor at
# which Border draws nothing — so the partial render is the kind that
# would normally produce a busted card with side bars, content, and
# only the bottom border. The parking pre-pass intercepts that and
# folds card 0 entirely; the rendered list compacts upward and the
# focused card sits at viewport row 0 with both borders intact.
my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

for <alpha beta gamma> Z 8, 10, 5 -> ($label, $h) {
    my $text   = Selkie::Widget::Text.new(text => $label, sizing => Sizing.flex);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($text);
    $cards.add-item($text, root => $border, height => $h, :$border,
                    min-display-height => 6);
}

$cards.select-index(1);

print render-to-string($cards, rows => 14, cols => 20);
