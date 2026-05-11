NAME
====

Selkie::Widget::Spinner - Tiny animated loading indicator

SYNOPSIS
========

```raku
use Selkie::Widget::Spinner;
use Selkie::Sizing;

my $spinner = Selkie::Widget::Spinner.new(sizing => Sizing.fixed(1));

# Drive animation from the main loop's frame callback
$app.on-frame: { $spinner.tick };
```

DESCRIPTION
===========

A one-cell widget that cycles through a set of spinner frames, giving a lightweight "something is happening" signal. Use it next to a status message during async work, or anywhere you'd reach for a small activity indicator.

Not focusable (it's display-only). Animation is manually advanced via `tick` — call it from `$app.on-frame`. Throttling is wall-clock based: `tick` is safe to call many times per second, and the animation advances at most once per `interval` seconds (default 0.1 = 10fps). This makes the visible rate independent of how often the event loop iterates, which matters on fast-input scenarios (e.g. mouse events flooding the queue).

Several built-in frame sets are provided as class constants:

  * `BRAILLE` — the default; `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`. Smooth-looking in most terminals.

  * `DOTS` — `⣾⣽⣻⢿⡿⣟⣯⣷`. Chunkier braille variant.

  * `LINE` — `|/-\`. Classic ASCII.

  * `CIRCLE` — `◐◓◑◒`. Half-circles rotating.

  * `ARROW` — `←↖↑↗→↘↓↙`. Pointing arrows.

Or pass your own array of strings via `frames`.

EXAMPLES
========

Side-by-side with a status message
----------------------------------

```raku
my $row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $spinner = Selkie::Widget::Spinner.new(sizing => Sizing.fixed(2));
my $status  = Selkie::Widget::Text.new(text => 'Loading...', sizing => Sizing.flex);
$row.add($spinner);
$row.add($status);
$app.on-frame: { $spinner.tick };
```

Hide when idle
--------------

Spinners look confusing when they're still animating in an idle app. Toggle visibility by swapping between the spinner and an empty Text:

```raku
$app.store.subscribe-with-callback(
    'job-running',
    -> $s { $s.get-in('job', 'running') // False },
    -> Bool $running {
        # Repoint $row's first child to spinner-or-blank
        ...
    },
    $row,
);
```

Simpler: just stop calling `tick` when idle. The spinner freezes on its last frame rather than disappearing — fine for many use cases.

Custom frame set
----------------

```raku
my $custom = Selkie::Widget::Spinner.new(
    frames   => <⣀ ⣄ ⣤ ⣦ ⣶ ⣷ ⣿>,
    interval => 0.05,     # 20fps — snappy
    sizing   => Sizing.fixed(1),
);
```

SEE ALSO
========

  * [Selkie::Widget::ProgressBar](Selkie--Widget--ProgressBar.md) — determinate progress with optional indeterminate bounce

  * [Selkie::Widget::Toast](Selkie--Widget--Toast.md) — transient message overlay

### has Positional @.frames

Classic braille spinner — the default frame set. Chunkier filled-braille set. ASCII vertical bar / slash rotation. Rotating half-circles. Rotating arrow octants. The array of strings to cycle through. Defaults to `BRAILLE`.

### has Real $.interval

Minimum wall-clock interval between frame advances, in seconds. Default 0.1 = 10fps, which looks smooth without being distracting. Higher values give a calmer spinner; lower values a faster one.

### has Selkie::Style $.style

Optional style override for the rendered character. If undefined, the theme's `text-highlight` slot is used.

### method new

```raku
method new(
    *%args
) returns Selkie::Widget::Spinner
```

Constructor. Defaults `focusable` to False (the spinner is display-only). Common attributes: `:frames` (override the frame set), `:interval` (advance throttle, default 0.1s), `:style`.

### method tick

```raku
method tick() returns Mu
```

Advance the animation if at least `interval` seconds have passed since the previous advance. Call from `$app.on-frame`. Safe to call many times per second — the wall-clock check throttles so the animation rate is independent of how often the event loop iterates.

### method reset

```raku
method reset() returns Mu
```

Reset to the first frame. Useful when starting a new operation to give a consistent visual cue.

### method current-frame

```raku
method current-frame() returns Str
```

The current frame string. Useful if you want to render the spinner yourself somewhere else.

