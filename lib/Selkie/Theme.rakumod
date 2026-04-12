unit class Selkie::Theme;

use Selkie::Style;

# Base colors
has Selkie::Style $.base is required;
has Selkie::Style $.border is required;
has Selkie::Style $.border-focused is required;

# Text
has Selkie::Style $.text is required;
has Selkie::Style $.text-dim is required;
has Selkie::Style $.text-highlight is required;

# Input
has Selkie::Style $.input is required;
has Selkie::Style $.input-focused is required;
has Selkie::Style $.input-placeholder is required;

# Scrollbar
has Selkie::Style $.scrollbar-track is required;
has Selkie::Style $.scrollbar-thumb is required;

# Split divider
has Selkie::Style $.divider is required;

# Extensibility
has Selkie::Style %.custom;

method slot(Str:D $name --> Selkie::Style) {
    %!custom{$name} // $!base;
}

method default(--> Selkie::Theme) {
    Selkie::Theme.new(
        base              => Selkie::Style.new(fg => 0xC0C0C0, bg => 0x1A1A2E),
        border            => Selkie::Style.new(fg => 0x4A4A6A, bg => 0x1A1A2E),
        border-focused    => Selkie::Style.new(fg => 0x7AA2F7, bg => 0x1A1A2E, bold => True),
        text              => Selkie::Style.new(fg => 0xC0C0C0),
        text-dim          => Selkie::Style.new(fg => 0x606080),
        text-highlight    => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
        input             => Selkie::Style.new(fg => 0xC0C0C0, bg => 0x24243E),
        input-focused     => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x2A2A4A),
        input-placeholder => Selkie::Style.new(fg => 0x606080, bg => 0x24243E, italic => True),
        scrollbar-track   => Selkie::Style.new(fg => 0x2A2A4A, bg => 0x1A1A2E),
        scrollbar-thumb   => Selkie::Style.new(fg => 0x7AA2F7, bg => 0x1A1A2E),
        divider           => Selkie::Style.new(fg => 0x3A3A5A, bg => 0x1A1A2E),
    );
}
