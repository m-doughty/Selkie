use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::ListView;
use Selkie::Widget::Border;
use Selkie::Sizing;

my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
$list.set-items(<alpha beta gamma>);

my $border = Selkie::Widget::Border.new(title => 'List', sizing => Sizing.flex);
$border.set-content($list);

print render-to-string($border, rows => 6, cols => 20);
