unit class Selkie::Style;

use Notcurses::Native::Types;

has UInt $.fg;
has UInt $.bg;
has Bool $.bold = False;
has Bool $.italic = False;
has Bool $.underline = False;
has Bool $.strikethrough = False;

method styles(--> UInt) {
    my UInt $s = 0;
    $s +|= NCSTYLE_BOLD      if $!bold;
    $s +|= NCSTYLE_ITALIC    if $!italic;
    $s +|= NCSTYLE_UNDERLINE if $!underline;
    $s +|= NCSTYLE_STRUCK    if $!strikethrough;
    $s;
}

method merge(Selkie::Style $override --> Selkie::Style) {
    Selkie::Style.new(
        fg            => $override.fg            // $!fg,
        bg            => $override.bg            // $!bg,
        bold          => $override.bold          || $!bold,
        italic        => $override.italic        || $!italic,
        underline     => $override.underline     || $!underline,
        strikethrough => $override.strikethrough || $!strikethrough,
    );
}
