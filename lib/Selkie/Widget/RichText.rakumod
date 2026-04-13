=begin pod

=head1 NAME

Selkie::Widget::RichText - Styled text built from C<Span> fragments

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Style;
use Selkie::Sizing;

my $rich = Selkie::Widget::RichText.new(sizing => Sizing.flex);
$rich.set-content([
    Selkie::Widget::RichText::Span.new(
        text  => 'alice: ',
        style => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    ),
    Selkie::Widget::RichText::Span.new(
        text  => 'Hey, how are you?',
        style => Selkie::Style.new(fg => 0xEEEEEE),
    ),
]);

=end code

=head1 DESCRIPTION

Like L<Selkie::Widget::Text>, but each fragment can have its own style.
Word-wraps across span boundaries while preserving styles — if a span
is split across two lines, both halves render with that span's style.

Supports partial rendering via C<render-region>, so it composes
correctly inside C<Selkie::Widget::ScrollView>. The C<truncated-top>
and C<truncated-bottom> flags insert "…" ellipsis lines when content
would overflow — useful for showing a preview snippet.

=head1 EXAMPLES

=head2 Colour-coded message

=begin code :lang<raku>

my $red = Selkie::Style.new(fg => 0xFF5555, bold => True);
$rich.set-content([
    Selkie::Widget::RichText::Span.new(text => 'Error: ', style => $red),
    Selkie::Widget::RichText::Span.new(text => 'file not found'),
]);

=end code

=head2 Truncated preview

=begin code :lang<raku>

my $preview = Selkie::Widget::RichText.new(
    sizing           => Sizing.fixed(3),
    truncated-bottom => True,
);
# Content longer than 3 lines shows the first 2 lines + '…'

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::RichText::Span> — the fragment value class
=item L<Selkie::Widget::Text> — simpler, single-style variant
=item L<Selkie::Widget::ScrollView> — for scrolling long rich text

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

# Span lives in its own module — `unit class` is one class per file.
use Selkie::Widget::RichText::Span;

unit class Selkie::Widget::RichText does Selkie::Widget;

has Selkie::Widget::RichText::Span @!spans;
has @!wrapped-lines;

#| When set to True, overflow at the bottom is shown as a "…" line in
#| place of the last visible wrapped line.
has Bool $.truncated-bottom is rw = False;

#| When True, overflow at the top is shown as a "…" line in place of
#| the first visible wrapped line (displays the most recent content).
has Bool $.truncated-top is rw = False;

#|( Replace the displayed content with the given list of Spans. The
    wrap cache is invalidated; the next render rebuilds it. )
method set-content(@spans) {
    @!spans = @spans;
    @!wrapped-lines = ();
    self.mark-dirty;
}

#| The current spans as a List.
method spans(--> List) { @!spans.List }

#| Number of wrapped lines at the current width. Used by ScrollView.
method logical-height(--> UInt) {
    self!rewrap unless @!wrapped-lines;
    @!wrapped-lines.elems;
}

method render() {
    return without self.plane;
    self!rewrap;

    my $default-style = self.theme.text;
    ncplane_erase(self.plane);

    my UInt $visible = self.rows min @!wrapped-lines.elems;
    my Bool $has-overflow = @!wrapped-lines.elems > self.rows && $visible > 0;
    my $dim = Selkie::Style.new(fg => 0x606080);

    if $!truncated-top && $has-overflow {
        # Show LAST lines with '...' as first line
        my $offset = @!wrapped-lines.elems - $visible + 1;  # +1 for the '...' line
        $offset = $offset max 0;
        self!render-line(0, (Selkie::Widget::RichText::Span.new(text => '...', style => $dim),), $default-style);
        for 1 ..^ $visible -> $row {
            my $src = $offset + $row - 1;
            last if $src >= @!wrapped-lines.elems;
            self!render-line($row, @!wrapped-lines[$src], $default-style);
        }
    } elsif $!truncated-bottom && $has-overflow {
        # Show FIRST lines with '...' as last line
        for ^($visible - 1) -> $row {
            self!render-line($row, @!wrapped-lines[$row], $default-style);
        }
        self!render-line($visible - 1, (Selkie::Widget::RichText::Span.new(text => '...', style => $dim),), $default-style);
    } else {
        for ^$visible -> $row {
            self!render-line($row, @!wrapped-lines[$row], $default-style);
        }
    }
    self.clear-dirty;
}

method render-region(UInt :$offset, UInt :$height) {
    return without self.plane;
    self!rewrap;

    my $default-style = self.theme.text;
    ncplane_erase(self.plane);

    my UInt $end = ($offset + $height) min @!wrapped-lines.elems;
    my UInt $row = 0;
    for $offset ..^ $end -> $line-idx {
        self!render-line($row++, @!wrapped-lines[$line-idx], $default-style);
    }
    self.clear-dirty;
}

method !render-line(UInt $row, @line-spans, Selkie::Style $default-style) {
    my UInt $col = 0;
    for @line-spans -> $span {
        my $s = $span.style // $default-style;
        self.apply-style($s);
        ncplane_putstr_yx(self.plane, $row, $col, $span.text);
        $col += $span.text.chars;
    }
}

method !rewrap() {
    my UInt $width = self.cols max 1;
    @!wrapped-lines = ();

    # Flatten all spans into a single stream, splitting on newlines
    my @logical-lines = self!split-spans-by-newline;

    for @logical-lines -> @line-spans {
        self!wrap-line(@line-spans, $width);
    }

    @!wrapped-lines.push([Selkie::Widget::RichText::Span.new(text => '')]) unless @!wrapped-lines;
}

method !split-spans-by-newline(--> Array) {
    my @result;
    my @current-line;

    for @!spans -> $span {
        # Split on any newline (handles \n, \r\n, \r)
        # :v preserves separators as Match objects between parts
        my @parts = $span.text.split(/\n/, :v);
        for @parts -> $part {
            if $part ~~ Match {
                # Newline separator — start a new line
                @result.push(@current-line.clone);
                @current-line = ();
            } else {
                @current-line.push(Selkie::Widget::RichText::Span.new(text => $part, style => $span.style))
                    if $part.chars > 0;
            }
        }
    }
    @result.push(@current-line);
    @result;
}

method !wrap-line(@line-spans, UInt $width) {
    my @current-row;
    my UInt $col = 0;

    for @line-spans -> $span {
        my $text = $span.text;
        my $style = $span.style;

        # Split span into tokens: alternating words and whitespace
        my @tokens = $text.comb(/ \S+ | \s+ /);

        for @tokens -> $token {
            my $token-len = $token.chars;

            # If adding this token would overflow the line
            if $col + $token-len > $width && $col > 0 {
                # If it's whitespace at a line break, skip it
                if $token ~~ /^ \s+ $/ {
                    @!wrapped-lines.push(@current-row.clone);
                    @current-row = ();
                    $col = 0;
                    next;
                }

                # Wrap: start a new line
                @!wrapped-lines.push(@current-row.clone);
                @current-row = ();
                $col = 0;
            }

            # If a single token is wider than the entire line, hard-wrap it
            if $token-len > $width {
                my $pos = 0;
                while $pos < $token-len {
                    my $remaining = $width - $col;
                    my $chunk-len = ($token-len - $pos) min $remaining;
                    my $chunk = $token.substr($pos, $chunk-len);
                    @current-row.push(Selkie::Widget::RichText::Span.new(text => $chunk, :$style));
                    $col += $chunk-len;
                    $pos += $chunk-len;
                    if $col >= $width && $pos < $token-len {
                        @!wrapped-lines.push(@current-row.clone);
                        @current-row = ();
                        $col = 0;
                    }
                }
            } else {
                # Skip leading whitespace on a new line
                next if $col == 0 && $token ~~ /^ \s+ $/;
                @current-row.push(Selkie::Widget::RichText::Span.new(text => $token, :$style));
                $col += $token-len;
            }
        }
    }

    # Push the final row (even if empty — preserves blank lines)
    @!wrapped-lines.push(@current-row);
}

method !on-resize() {
    # Wrapping is column-sensitive; recompute the wrap cache so the
    # next render lays spans out against the new width.
    self!rewrap;
}
