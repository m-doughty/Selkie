=begin pod

=head1 NAME

Selkie::Widget::RichText::Span - A fragment of styled text within a RichText

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::RichText::Span;
use Selkie::Style;

my $span = Selkie::Widget::RichText::Span.new(
    text  => 'Error: ',
    style => Selkie::Style.new(fg => 0xFF5555, bold => True),
);

=end code

=head1 DESCRIPTION

A simple value class — holds a string and an optional style. Used
exclusively as an element in the array passed to
C<Selkie::Widget::RichText.set-content>. The RichText widget word-wraps
across span boundaries while preserving each span's style on the
characters it owns.

The class has its own file so that C<unit class> can declare it
without conflicting with C<Selkie::Widget::RichText> itself.

=head1 SEE ALSO

=item L<Selkie::Widget::RichText> — the widget that renders a list of spans
=item L<Selkie::Style> — styling attributes

=end pod

unit class Selkie::Widget::RichText::Span;

use Selkie::Style;

#| The text content of the span. Required.
has Str $.text is required;

#| Optional style. If undefined, the RichText's default theme style is
#| used for this span.
has Selkie::Style $.style;
