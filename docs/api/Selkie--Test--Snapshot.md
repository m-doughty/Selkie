NAME
====

Selkie::Test::Snapshot - Golden-file snapshot testing for widget rendering

SYNOPSIS
========

```raku
use Test;
use Selkie::Test::Snapshot;
use Selkie::Widget::Text;
use Selkie::Sizing;
use Selkie::Style;

my $header = Selkie::Widget::Text.new(
    text   => ' Selkie 1.0',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# First run: creates t/snapshots/header.snap from the rendered output.
# Subsequent runs: compares the current render against the saved file.
snapshot-ok $header, 'header', rows => 1, cols => 30;

done-testing;
```

DESCRIPTION
===========

Classic snapshot-testing pattern (Rails' `rspec-snapshot`, Jest's `toMatchSnapshot`, Elixir's Mneme). First run writes the rendered output of a widget to a golden file; subsequent runs render the widget again and fail if the output differs.

Under the hood:

  * Initialises notcurses against stdout in headless mode (no alternate screen, no signal handlers, banners suppressed, stderr redirected to silence notcurses shutdown chatter).

  * Sizes the stdplane to the requested dimensions.

  * Gives the widget that plane via `init-plane`.

  * Calls the widget's `render`.

  * Reads the rendered cells back with `ncplane_at_yx` row by row.

  * Shuts notcurses down cleanly.

Trailing whitespace is trimmed from each row; trailing empty rows are dropped so resizes don't churn snapshots unnecessarily.

**Currently snapshots capture character content only**, not styles. That's a deliberate v1 tradeoff — catches layout bugs, text mistakes, and most rendering regressions without the complexity of a style-aware snapshot format.

Practical consequence: widgets whose state changes are style-only (e.g. `ListView` cursor, `Button` focus highlight, `Checkbox` toggle color) won't produce a different snapshot between states. Test those via the widget's attributes or the `Selkie::Test::Keys` + event assertions directly, not via snapshots.

WORKFLOW
========

  * **First run or missing snapshot:** the file is created and the test passes.

  * **Matching snapshot:** the test passes silently.

  * **Differing snapshot:** the test fails, and a diff is printed to TAP diagnostics.

To accept new output (when an intentional change makes existing snapshots stale), re-run with the update env var:

```bash
SELKIE_UPDATE_SNAPSHOTS=1 prove6 -l t
```

Every snapshot-ok call overwrites its file in update mode. Then re-run without the flag to confirm everything matches.

EXAMPLES
========

A basic widget
--------------

```raku
snapshot-ok $my-widget, 'my-widget-default', rows => 10, cols => 40;
```

Testing multiple states of the same widget
------------------------------------------

```raku
use Selkie::Test::Keys;

my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
$list.set-items(<alpha beta gamma>);

snapshot-ok $list, 'list-initial',  rows => 5, cols => 20;

press-key($list, 'down');
snapshot-ok $list, 'list-cursor-1', rows => 5, cols => 20;

press-key($list, 'end');
snapshot-ok $list, 'list-cursor-end', rows => 5, cols => 20;
```

Custom snapshot directory
-------------------------

```raku
snapshot-ok $widget, 'thing', :rows(4), :cols(20), dir => 'xt/snaps';
```

FILE FORMAT
===========

Snapshots are plain UTF-8 text files. One line per rendered row; trailing whitespace stripped; trailing blank rows removed; final newline appended.

No metadata, no escaped characters beyond what the widget actually rendered. This means snapshot files render legibly on GitHub and are trivial to diff by eye:

    ┌──────────────┐
    │ Hello, Selkie│
    └──────────────┘

CAVEATS
=======

  * **Styles aren't captured.** Two widgets that render the same glyphs in different colors produce identical snapshots. If style matters, test it via the widget's attributes directly.

  * **Non-ASCII width.** Snapshots use one-character-per-cell. Wide characters (CJK, emoji) may render over multiple cells; the captured output reflects what `ncplane_at_yx` returns at each cell position.

  * **Real notcurses init.** Each call spins notcurses up and tears it down. ~50-100ms per snapshot. For small test suites this is fine; for large ones, group related snapshots in the same test and share context if performance matters.

  * **Headless-friendly.** Init is done against a pipe-compatible output, so tests run in CI without a TTY. Output to stderr is silenced during init/stop to avoid the notcurses "signals weren't registered" diagnostic leaking into TAP.

SEE ALSO
========

  * [Selkie::Test::Keys](Selkie--Test--Keys.md) — simulate events before taking a snapshot

  * [Selkie::Test::Focus](Selkie--Test--Focus.md) — focus-gated rendering paths

### sub render-to-string

```raku
sub render-to-string(
    Selkie::Widget $widget,
    Int :$rows where { ... } = 24,
    Int :$cols where { ... } = 80
) returns Str
```

Render a widget to a plain-text string via a shared headless notcurses instance. Returns the rendered cells row-by-row, joined with newlines. Trailing whitespace on each line is stripped, and trailing blank lines are removed. The widget is given its own plane as a child of the stdplane, sized to `$rows` × `$cols`. Containers that manage child planes in their `render` work correctly — the standard mount path is exercised. The notcurses instance persists across calls within a test process (init is once-per-process). The widget's plane is destroyed after each call so renders don't leak.

### sub snapshot-ok

```raku
sub snapshot-ok(
    Selkie::Widget $widget,
    Str:D $name,
    Int :$rows where { ... } = 24,
    Int :$cols where { ... } = 80,
    Str :$dir = "t/snapshots"
) returns Mu
```

Test assertion: render the widget to `$rows` × `$cols` and compare against a stored snapshot file at `$dir/$name.snap`. =item First run or missing file: the snapshot is created and the test passes. =item Matching output: the test passes. =item Differing output: the test fails and a unified-ish diff is printed as TAP diagnostics. Set the env var `SELKIE_UPDATE_SNAPSHOTS` to a truthy value to overwrite existing snapshots with current output. The snapshot directory defaults to `t/snapshots` and is auto-created on first use.

