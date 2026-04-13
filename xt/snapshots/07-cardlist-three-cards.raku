use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::Text;
use Selkie::Sizing;

my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

for <alpha beta gamma> -> $label {
    my $text   = Selkie::Widget::Text.new(text => $label, sizing => Sizing.flex);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($text);
    $cards.add-item($text, root => $border, height => 3, :$border);
}

print render-to-string($cards, rows => 12, cols => 22);
