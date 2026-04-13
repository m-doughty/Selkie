use lib 'lib';
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Widget::TextInput;
use Selkie::Widget::PasswordStrength;
use Selkie::Layout::VBox;
use Selkie::Sizing;

# Render the strength meter at each of five input strengths. Holds
# input+meter references outside the builder so nothing gets GC'd
# between construction and render.

my @inputs;
my @meters;

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);

for <abc password Password1 Password1! Correct-Horse-Battery-Staple!!> -> $pw {
    my $input = Selkie::Widget::TextInput.new(
        sizing    => Sizing.fixed(1),
        mask-char => '*',
    );
    $input.set-text($pw);
    @inputs.push($input);

    my $meter = Selkie::Widget::PasswordStrength.new(
        sizing => Sizing.fixed(1),
        input  => $input,
    );
    @meters.push($meter);

    $root.add: Selkie::Widget::Text.new(
        text   => "pw: $pw",
        sizing => Sizing.fixed(1),
    );
    $root.add($meter);
    $root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));
}

print render-to-string($root, rows => 16, cols => 60);
