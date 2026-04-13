use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Sizing;

my $text = Selkie::Widget::Text.new(
    text   => 'hello, selkie',
    sizing => Sizing.fixed(1),
);

print render-to-string($text, rows => 1, cols => 20);
