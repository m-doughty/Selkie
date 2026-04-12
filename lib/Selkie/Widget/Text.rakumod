use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;

unit class Selkie::Widget::Text does Selkie::Widget;

has Str $.text = '';
has Selkie::Style $.style;
has @!wrapped-lines;

method set-text(Str:D $t) {
    $!text = $t;
    self!rewrap;
    self.mark-dirty;
}

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
            # Word-wrap: break at word boundaries
            my @words = $line.comb(/ \S+ | \s+ /);
            my $current = '';
            for @words -> $word {
                if $current.chars + $word.chars > $width && $current.chars > 0 {
                    @!wrapped-lines.push($current);
                    $current = '';
                    next if $word ~~ /^ \s+ $/;  # skip leading whitespace on new line
                }
                # Hard-wrap words longer than width
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

method resize(UInt $rows, UInt $cols) {
    return if $rows == self.rows && $cols == self.cols;
    my $old-cols = self.cols;
    self!apply-resize($rows, $cols);
    self.mark-dirty;
    self!rewrap if $cols != $old-cols;
}
