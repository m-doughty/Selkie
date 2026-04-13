NAME
====

Selkie::Widget::TextStream - Append-only log with ring buffer and auto-scroll

SYNOPSIS
========

```raku
use Selkie::Widget::TextStream;
use Selkie::Sizing;

my $log = Selkie::Widget::TextStream.new(
    sizing    => Sizing.flex,
    max-lines => 10_000,
);

$log.append('Starting up...');
$log.append('Connected', style => Selkie::Style.new(fg => 0x9ECE6A));

# Or drive from a Supply — each emission becomes a line
$log.start-supply($lines-from-somewhere);
```

DESCRIPTION
===========

A scrollable log of text lines. Internally a ring buffer — bounded by `max-lines` — so it's safe to append from high-volume sources without unbounded memory growth.

Auto-scrolls to the bottom on append while the user is "at the end" (the default state). When the user scrolls up with arrow keys or the mouse wheel, auto-scroll pauses until they scroll back to the bottom.

Arrow keys, Page Up/Down, Home/End, and the scroll wheel are handled when the widget is focused.

EXAMPLES
========

A streaming chat view
---------------------

Pipe every message in a store-held array into the stream:

```raku
$app.store.subscribe-with-callback(
    'message-log',
    -> $s { $s.get-in('messages') // [] },
    -> @msgs { $log.clear; $log.append(.<text>) for @msgs },
    $log,
);
```

Colour-coded log levels
-----------------------

```raku
$log.append("INFO  $line", style => Selkie::Style.new(fg => 0xC0C0C0));
$log.append("WARN  $line", style => Selkie::Style.new(fg => 0xFFCC00));
$log.append("ERROR $line", style => Selkie::Style.new(fg => 0xFF5555, bold => True));
```

SEE ALSO
========

  * [Selkie::Widget::Text](Selkie--Widget--Text.md) — static styled block of text

  * [Selkie::Widget::ScrollView](Selkie--Widget--ScrollView.md) — generic virtual-scrolling container

### has UInt $.max-lines

Maximum number of lines retained. Older lines are discarded as new ones arrive (ring buffer). Defaults to 10,000.

### has Bool $.show-scrollbar

Whether to render the vertical scrollbar on the right edge when the buffer is taller than the viewport.

### method logical-height

```raku
method logical-height() returns UInt
```

Number of lines currently in the buffer.

### method supply

```raku
method supply() returns Supply
```

Tap this to get every line as it's appended. Useful for mirroring output to an external sink (log file, network).

### method start-supply

```raku
method start-supply(
    Supply $s
) returns Mu
```

Forward every value from a Supply into the stream, coerced to string and split on newlines. Convenience for piping LLM streams, subprocess output, etc.

### method append

```raku
method append(
    Str:D $text,
    Selkie::Style :$style
) returns Mu
```

Append text. If the text contains newlines, each line becomes a separate buffer entry. The optional `:style` decorates those lines without affecting the rest of the buffer.

### method scroll-to

```raku
method scroll-to(
    Int $row where { ... }
) returns Mu
```

Scroll to a specific row (0 = top). Above the max offset is clamped. Auto-follow is re-enabled when you scroll to the end.

### method scroll-by

```raku
method scroll-by(
    Int $delta
) returns Mu
```

Scroll by a relative delta. Negative goes up, positive goes down.

### method scroll-to-start

```raku
method scroll-to-start() returns Mu
```

Jump to the top of the buffer. Disables auto-follow until the user scrolls back to the end.

### method scroll-to-end

```raku
method scroll-to-end() returns Mu
```

Jump to the bottom and re-enable auto-follow.

### method clear

```raku
method clear() returns Mu
```

Empty the buffer and reset to the top.

