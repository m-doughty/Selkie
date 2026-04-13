=begin pod

=head1 NAME

Selkie::Widget::Text - Static styled text with word-wrap

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Text;
use Selkie::Style;
use Selkie::Sizing;

my $header = Selkie::Widget::Text.new(
    text   => ' My App',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Mutate later
$header.set-text(' My App — logged in as Alice');

=end code

=head1 DESCRIPTION

A block of text rendered onto a single plane. Word-wraps automatically
when the text exceeds the widget's width — words longer than the line
are hard-broken at the character level.

Styled via the optional C<style> attribute. If omitted, inherits the
theme's C<text> slot.

C<Text> implements C<render-region(offset, height)>, so it plays
correctly with C<Selkie::Widget::ScrollView> for long content.

=head1 EXAMPLES

=head2 A header and footer

=begin code :lang<raku>

$vbox.add: Selkie::Widget::Text.new(
    text   => 'Selkie App',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);
$vbox.add: $main-content;
$vbox.add: Selkie::Widget::Text.new(
    text   => 'Ctrl+Q: quit  —  ?: help',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x888888),
);

=end code

=head2 Driven by the store

Set up a subscription that updates the text whenever state changes:

=begin code :lang<raku>

my $status = Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));
$app.store.subscribe-with-callback(
    'status-line',
    -> $s { "{$s.get-in('user', 'name') // 'guest'} — {$s.get-in('messages').elems} unread" },
    -> $text { $status.set-text($text) },
    $status,
);

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::RichText> — styled spans within one block of text
=item L<Selkie::Widget::TextStream> — append-only log with ring buffer and auto-scroll

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

unit class Selkie::Widget::Text does Selkie::Widget;

#| The text to render. Can include newlines — each line is wrapped
#| independently.
has Str $.text = '';

#| Optional style override. If undefined, the theme's C<text> slot is used.
has Selkie::Style $.style;

has @!wrapped-lines;

#| Replace the displayed text. Re-wraps and marks the widget dirty.
method set-text(Str:D $t) {
    $!text = $t;
    self!rewrap;
    self.mark-dirty;
}

#| Replace the style override. Pass an undefined Selkie::Style to
#| revert to the theme default.
method set-style(Selkie::Style $s) {
    $!style = $s;
    self.mark-dirty;
}

#| Number of lines the text wraps to at the current width. Used by
#| C<ScrollView> to compute scrollable extent.
method logical-height(--> UInt) {
    self!rewrap unless @!wrapped-lines;
    @!wrapped-lines.elems;
}

method render() {
    return without self.plane;
    self!rewrap;

    my $s = $!style // self.theme.text;
    self.apply-style($s);
    ncplane_erase(self.plane);

    my UInt $visible = self.rows min @!wrapped-lines.elems;
    for ^$visible -> $row {
        ncplane_putstr_yx(self.plane, $row, 0, @!wrapped-lines[$row]);
    }
    self.clear-dirty;
}

#|( Render only a slice of the wrapped lines, starting at C<offset> and
    going for C<height> rows. Used by C<ScrollView> for partial-viewport
    rendering. )
method render-region(UInt :$offset, UInt :$height) {
    return without self.plane;
    self!rewrap unless @!wrapped-lines;

    my $s = $!style // self.theme.text;
    self.apply-style($s);
    ncplane_erase(self.plane);

    my UInt $end = ($offset + $height) min @!wrapped-lines.elems;
    my UInt $row = 0;
    for $offset ..^ $end -> $line-idx {
        ncplane_putstr_yx(self.plane, $row++, 0, @!wrapped-lines[$line-idx]);
    }
    self.clear-dirty;
}

method !rewrap() {
    my UInt $width = self.cols max 1;
    @!wrapped-lines = ();
    for $!text.lines -> $line {
        if $line.chars <= $width {
            @!wrapped-lines.push($line);
        } else {
            my @words = $line.comb(/ \S+ | \s+ /);
            my $current = '';
            for @words -> $word {
                if $current.chars + $word.chars > $width && $current.chars > 0 {
                    @!wrapped-lines.push($current);
                    $current = '';
                    next if $word ~~ /^ \s+ $/;
                }
                if $word.chars > $width && $current.chars == 0 {
                    my $pos = 0;
                    while $pos < $word.chars {
                        my $chunk = $word.substr($pos, $width);
                        if $pos + $width < $word.chars {
                            @!wrapped-lines.push($chunk);
                        } else {
                            $current = $chunk;
                        }
                        $pos += $width;
                    }
                } else {
                    $current ~= $word;
                }
            }
            @!wrapped-lines.push($current) if $current.chars > 0;
        }
    }
    @!wrapped-lines.push('') unless @!wrapped-lines;
}

method !on-resize() {
    # Text wrapping depends on column width; when handle-resize fires
    # for a width change, refresh the cached wrap so the next render
    # lays the string out correctly.
    self!rewrap;
}
