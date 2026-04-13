use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::TabBar;
use Selkie::Layout::VBox;
use Selkie::Widget::Text;
use Selkie::Sizing;

# Two TabBars side-by-side: the upper one focused, the lower not.
# Snapshot captures the "▶ " focus indicator on the focused bar (vs
# blank padding when not), plus the active-tab brackets which are
# always present so users can see WHICH tab is current even when
# their bar isn't focused. Background-colour differentiation isn't
# visible in snapshots — they capture EGC only — but the chevron
# carries the focus signal in monochrome too.

my $vbox = Selkie::Layout::VBox.new(sizing => Sizing.flex);

my $focused = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$focused.add-tab(name => 'identity', label => 'Identity');
$focused.add-tab(name => 'behavior', label => 'Behavior');
$focused.add-tab(name => 'dialogue', label => 'Dialogue');
$focused.select-index(1);
$focused.set-focused(True);
$vbox.add($focused);

$vbox.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));

my $unfocused = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$unfocused.add-tab(name => 'identity', label => 'Identity');
$unfocused.add-tab(name => 'behavior', label => 'Behavior');
$unfocused.add-tab(name => 'dialogue', label => 'Dialogue');
$unfocused.select-index(1);
# left unfocused — set-focused(False) is the default
$vbox.add($unfocused);

print render-to-string($vbox, rows => 3, cols => 60);
