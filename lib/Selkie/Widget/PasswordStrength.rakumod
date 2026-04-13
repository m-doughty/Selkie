=begin pod

=head1 NAME

Selkie::Widget::PasswordStrength - Live password-strength meter bound to a TextInput

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::TextInput;
use Selkie::Widget::PasswordStrength;
use Selkie::Sizing;

my $pw = Selkie::Widget::TextInput.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Enter password...',
    mask-char   => '*',
);

my $meter = Selkie::Widget::PasswordStrength.new(
    sizing => Sizing.fixed(1),
    input  => $pw,
);

$vbox.add($pw);
$vbox.add($meter);

=end code

=head1 DESCRIPTION

Non-focusable widget that subscribes to a C<TextInput>'s C<on-change>
Supply and renders a five-level strength meter in response.

Scoring is a simple length-plus-character-class heuristic — long
enough for "password1" to look weak and "Correct Horse Battery Staple
Example!" to look strong, without pulling in a dictionary or an
external dependency. For serious analysis use C<zxcvbn>; this is
meant to give users directional feedback while they type.

=head2 Levels

=item B<weak>        (score < 20)  — red
=item B<fair>        (score < 40)  — orange
=item B<good>        (score < 60)  — yellow
=item B<strong>      (score < 80)  — light green
=item B<very strong> (score >= 80) — green

=head2 Score formula

    score = min(100, length * (1 + 0.5 * (classes-1)) * class-bonus)

Where C<classes> is the count of used character classes
(lowercase / uppercase / digits / symbols) and C<class-bonus> rewards
mixed-class passwords.

=head1 ATTRIBUTES

=item C<input> — the C<TextInput> to watch. Required.
=item C<show-label> — include the "weak"/"fair"/etc. label beside the
  bar. Default True.

=end pod

use Selkie::Widget;
use Selkie::Widget::TextInput;
use Selkie::Style;

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

unit class Selkie::Widget::PasswordStrength does Selkie::Widget;

has Selkie::Widget::TextInput $.input is required;
has Bool $.show-label = True;

has UInt $!score = 0;
has Str $!label = '';
has UInt $!colour = 0x606060;

my constant @LEVELS =
    { threshold =>   0, label => '',            colour => 0x404040 },
    { threshold =>   1, label => 'weak',        colour => 0xE06060 },
    { threshold =>  20, label => 'fair',        colour => 0xE0A040 },
    { threshold =>  40, label => 'good',        colour => 0xE0E040 },
    { threshold =>  60, label => 'strong',      colour => 0x80E060 },
    { threshold =>  80, label => 'very strong', colour => 0x40E080 },
;

method new(*%args --> Selkie::Widget::PasswordStrength) {
    %args<focusable> //= False;
    callwith(|%args);
}

submethod TWEAK() {
    # Bind to the watched input. Recompute on every keystroke.
    $!input.on-change.tap: -> $text {
        self!update($text);
    };
    # Initial compute in case the input already has content.
    self!update($!input.text);
}

method !update(Str $text) {
    $!score = score-password($text);
    my %lvl = level-for($!score);
    $!label = %lvl<label>;
    $!colour = %lvl<colour>;
    self.mark-dirty;
}

#| The most recent computed score, 0..100.
method score(--> UInt) { $!score }

#| The most recent level label ('', 'weak', ..., 'very strong').
method label(--> Str) { $!label }

method render() {
    return without self.plane;

    my UInt $cols = self.cols;
    return if $cols < 1;

    ncplane_erase(self.plane);

    # Reserve space for " <label>" if show-label and we have a label.
    my Str $suffix = ($!show-label && $!label.chars)
        ?? " {$!label}"
        !! '';
    my UInt $bar-width = ($cols - $suffix.chars) max 1;
    my UInt $filled = ($!score * $bar-width / 100).floor.UInt min $bar-width;

    self.apply-style(Selkie::Style.new(fg => $!colour));
    for ^$filled -> $x {
        ncplane_putstr_yx(self.plane, 0, $x, '█');
    }

    # Unfilled portion — dim.
    self.apply-style(Selkie::Style.new(fg => 0x303030));
    for $filled ..^ $bar-width -> $x {
        ncplane_putstr_yx(self.plane, 0, $x, '░');
    }

    # Label (if any) in the level colour.
    if $suffix.chars {
        self.apply-style(Selkie::Style.new(fg => $!colour, bold => True));
        ncplane_putstr_yx(self.plane, 0, $bar-width, $suffix);
    }

    self.clear-dirty;
}

# --- Scoring ------------------------------------------------------------

#|( Score a password 0..100 using a simple length + character-class
    heuristic. Intentionally simple and external-dependency-free.
    Not a substitute for zxcvbn; good enough to tell users
    directionally whether their choice is terrible, okay, or solid. )
sub score-password(Str $text --> UInt) is export(:DEFAULT, :scoring) {
    return 0 unless $text.chars;

    my $lower  = $text.contains(/<[a..z]>/);
    my $upper  = $text.contains(/<[A..Z]>/);
    my $digit  = $text.contains(/<[0..9]>/);
    my $symbol = $text.contains(/<-[a..z A..Z 0..9]>/);
    my $classes = ($lower, $upper, $digit, $symbol).grep(?*).elems;

    my $len = $text.chars;
    my $class-bonus = $classes >= 3 ?? 1.2
                    !! $classes == 2 ?? 1.0
                    !! 0.7;
    my $len-score = min($len * 4, 60);
    my $class-score = ($classes - 1) * 8;
    my $raw = ($len-score + $class-score) * $class-bonus;

    (min($raw, 100).Int max 0).UInt;
}

sub level-for(UInt $score --> Hash) is export(:scoring) {
    my %match = @LEVELS[0];
    for @LEVELS -> %l {
        %match = %l if $score >= %l<threshold>;
    }
    %match;
}
