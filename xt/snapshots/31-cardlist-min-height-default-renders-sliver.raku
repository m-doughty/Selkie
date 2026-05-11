use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::CardList;
use Selkie::Widget::Border;
use Selkie::Widget::Text;
use Selkie::Sizing;

# Backwards-compatibility regression guard: a CardList consumer that
# does NOT pass min-display-height (default = 1) keeps the historic
# behaviour of rendering whatever sliver fits. Same geometry as the
# leading-park scenario, but without min-display-height the leading
# card top-clips to a 4-row sliver — Border draws side bars + content
# + bottom border, which is exactly the "merge" symptom the new
# feature exists to suppress when callers opt in.
my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);

for <alpha beta gamma> Z 8, 10, 5 -> ($label, $h) {
    my $text   = Selkie::Widget::Text.new(text => $label, sizing => Sizing.flex);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
    $border.set-content($text);
    $cards.add-item($text, root => $border, height => $h, :$border);
}

$cards.select-index(1);

print render-to-string($cards, rows => 14, cols => 20);
