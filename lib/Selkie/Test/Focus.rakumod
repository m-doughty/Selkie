=begin pod

=head1 NAME

Selkie::Test::Focus - Focus simulation for widget tests without a real App

=head1 SYNOPSIS

=begin code :lang<raku>

use Test;
use Selkie::Test::Keys;
use Selkie::Test::Focus;
use Selkie::Widget::TextInput;

my $input = Selkie::Widget::TextInput.new;

# Run a block with the input focused — auto-unfocused after:
with-focus $input, {
    type-text($input, 'hello');
    press-key($input, 'enter');
};

is $input.text, 'hello', 'input received keystrokes while focused';
nok $input.is-focused, 'focus released after block';

=end code

=head1 DESCRIPTION

Most focusable widgets gate C<handle-event> on C<is-focused>:

    return False unless $!focused;

Writing that test setup (C<$w.set-focused(True)> + C<$w.set-focused(False)>)
for every widget test gets repetitive and hides the real intent. The
C<with-focus> block helper manages the focus state for you.

For widgets that don't have a C<set-focused> method (e.g. display-only
widgets), C<with-focus> is a no-op — the block still runs.

If you want to test multi-widget focus scenarios (like Tab cycling),
the App's C<focus> and C<focus-next> methods are the right API — use
those directly with a real C<Selkie::App>. This module is for single-widget
unit tests.

=head1 EXAMPLES

=head2 Assert focus-gated behaviour

=begin code :lang<raku>

my $btn = Selkie::Widget::Button.new(label => 'OK');

# Unfocused: key press ignored
my @unfocused = collect-from $btn.on-press, {
    press-key($btn, 'enter');
};
is @unfocused.elems, 0, 'unfocused button ignores Enter';

# Focused: key press consumed
my @focused = collect-from $btn.on-press, {
    with-focus $btn, {
        press-key($btn, 'enter');
    };
};
is @focused.elems, 1, 'focused button fires on Enter';

=end code

=head2 Exception-safe

C<with-focus> restores the unfocused state even if the block throws:

=begin code :lang<raku>

with-focus $widget, {
    die 'something broke';   # focus is still released after
};
CATCH { default { } }
nok $widget.is-focused, 'focus released despite exception';

=end code

=head1 SEE ALSO

=item L<Selkie::App> — C<focus>, C<focus-next>, C<focus-prev> for multi-widget focus
=item L<Selkie::Test::Keys> — synthesise keys to dispatch inside the with-focus block

=end pod

unit module Selkie::Test::Focus;

use Selkie::Widget;

#|( Run a block with the widget marked focused. If the widget has a
    C<set-focused(Bool)> method it's called with True before the block
    and False after (including on exception). Widgets without that
    method — e.g. display-only widgets — are passed through unchanged.

    Closes over the block with C<LEAVE> so focus is released even if
    the block throws. )
sub with-focus(Selkie::Widget $widget, &block) is export {
    my Bool $has-method = $widget.can('set-focused').Bool;
    $widget.set-focused(True) if $has-method;
    LEAVE { $widget.set-focused(False) if $has-method }
    block();
}
