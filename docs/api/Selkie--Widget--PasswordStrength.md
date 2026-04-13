NAME
====

Selkie::Widget::PasswordStrength - Live password-strength meter bound to a TextInput

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

Non-focusable widget that subscribes to a `TextInput`'s `on-change` Supply and renders a five-level strength meter in response.

Scoring is a simple length-plus-character-class heuristic — long enough for "password1" to look weak and "Correct Horse Battery Staple Example!" to look strong, without pulling in a dictionary or an external dependency. For serious analysis use `zxcvbn`; this is meant to give users directional feedback while they type.

Levels
------

  * **weak** (score < 20) — red

  * **fair** (score < 40) — orange

  * **good** (score < 60) — yellow

  * **strong** (score < 80) — light green

  * **very strong** (score >= 80) — green

Score formula
-------------

    score = min(100, length * (1 + 0.5 * (classes-1)) * class-bonus)

Where `classes` is the count of used character classes (lowercase / uppercase / digits / symbols) and `class-bonus` rewards mixed-class passwords.

ATTRIBUTES
==========

  * `input` — the `TextInput` to watch. Required.

  * `show-label` — include the "weak"/"fair"/etc. label beside the bar. Default True.

### method score

```raku
method score() returns UInt
```

The most recent computed score, 0..100.

### method label

```raku
method label() returns Str
```

The most recent level label ('', 'weak', ..., 'very strong').

### sub score-password

```raku
sub score-password(
    Str $text
) returns UInt
```

Score a password 0..100 using a simple length + character-class heuristic. Intentionally simple and external-dependency-free. Not a substitute for zxcvbn; good enough to tell users directionally whether their choice is terrible, okay, or solid.

