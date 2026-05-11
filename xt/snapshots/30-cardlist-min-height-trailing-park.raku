use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::Text;
use Selkie::Sizing;

# Selected mid-list (index 0). The trailing card would render below
# the focused row at display-h=4 (clipped at viewport bottom) — short
# of its min-display-height=6 and above the 3-row Border floor, so
# without the new feature it would draw a side-bar + content +
# bottom-border sliver flush against the focused card's bottom border.
# The main loop's trailing-park branch parks it instead.
my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

for <alpha beta> Z 10, 8 -> ($label, $h) {
    my $text   = Selkie::Widget::Text.new(text => $label, sizing => Sizing.flex);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($text);
    $cards.add-item($text, root => $border, height => $h, :$border,
                    min-display-height => 6);
}

$cards.select-index(0);

print render-to-string($cards, rows => 14, cols => 20);
