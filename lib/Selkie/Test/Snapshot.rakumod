=begin pod

=head1 NAME

Selkie::Test::Snapshot - Golden-file snapshot testing for widget rendering

=head1 SYNOPSIS

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

Classic snapshot-testing pattern (Rails' C<rspec-snapshot>, Jest's
C<toMatchSnapshot>, Elixir's Mneme). First run writes the rendered
output of a widget to a golden file; subsequent runs render the widget
again and fail if the output differs.

Under the hood:

=item Initialises notcurses against stdout in headless mode (no alternate screen, no signal handlers, banners suppressed, stderr redirected to silence notcurses shutdown chatter).
=item Sizes the stdplane to the requested dimensions.
=item Gives the widget that plane via C<init-plane>.
=item Calls the widget's C<render>.
=item Reads the rendered cells back with C<ncplane_at_yx> row by row.
=item Shuts notcurses down cleanly.

Trailing whitespace is trimmed from each row; trailing empty rows are
dropped so resizes don't churn snapshots unnecessarily.

B<By default, snapshots capture character content only>, not styles.
That's a deliberate tradeoff — catches layout bugs, text mistakes, and
most rendering regressions without the complexity of a style-aware
snapshot format. Diffs stay one-row-per-row legible in PR review.

Practical consequence: widgets whose state changes are style-only (e.g.
C<ListView> cursor, C<Button> focus highlight, C<Checkbox> toggle color)
won't produce a different snapshot between states. Test those via the
widget's attributes or the C<Selkie::Test::Keys> + event assertions
directly, not via plain snapshots.

For widgets where colour I<is> the regression — C<Heatmap>, multi-series
C<LineChart>, multi-bar C<BarChart>, themed elements — pass
C<:capture-styles> to C<render-to-string> (or C<snapshot-ok>). The
output then includes a parallel grid of style keys and a legend mapping
each key to C<(fg, bg, stylemask)>. The harness routes styled goldens
to C<xt/snapshots/golden-styled/> automatically (it detects the format
marker on the first line of stdout).

=head1 WORKFLOW

=item B<First run or missing snapshot:> the file is created and the test passes.
=item B<Matching snapshot:> the test passes silently.
=item B<Differing snapshot:> the test fails, and a diff is printed to TAP diagnostics.

To accept new output (when an intentional change makes existing snapshots
stale), re-run with the update env var:

=begin code :lang<bash>

SELKIE_UPDATE_SNAPSHOTS=1 prove6 -l t

=end code

Every snapshot-ok call overwrites its file in update mode. Then re-run
without the flag to confirm everything matches.

=head1 EXAMPLES

=head2 A basic widget

=begin code :lang<raku>

snapshot-ok $my-widget, 'my-widget-default', rows => 10, cols => 40;

=end code

=head2 Testing multiple states of the same widget

=begin code :lang<raku>

use Selkie::Test::Keys;

my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
$list.set-items(<alpha beta gamma>);

snapshot-ok $list, 'list-initial',  rows => 5, cols => 20;

press-key($list, 'down');
snapshot-ok $list, 'list-cursor-1', rows => 5, cols => 20;

press-key($list, 'end');
snapshot-ok $list, 'list-cursor-end', rows => 5, cols => 20;

=end code

=head2 Custom snapshot directory

=begin code :lang<raku>

snapshot-ok $widget, 'thing', :rows(4), :cols(20), dir => 'xt/snaps';

=end code

=head2 Style-aware snapshot

For widgets where colour or text style is the regression you care about,
opt into the styled format:

=begin code :lang<raku>

snapshot-ok $heatmap, 'heatmap-viridis', :rows(8), :cols(20), :capture-styles;

=end code

The captured output begins with C<=== styled-snapshot v1 ===> and
contains three blocks (C<--- glyphs --->, C<--- styles --->,
C<--- legend --->). The harness recognises the marker and stores the
golden under C<{$dir}/golden-styled/{$name}.snap> rather than
C<{$dir}/golden/{$name}.snap>.

Style equality is the C<(fg-rgb, bg-rgb, stylemask)> tuple. Cells with
no fg, no bg, and no styles get the C<.> key. Other tuples get
single-character keys (C<A>, C<B>, ..., C<Z>, C<a>, ..., C<z>, C<0>,
..., C<9>) in first-seen order.

=head1 FILE FORMAT

Snapshots are plain UTF-8 text files. One line per rendered row; trailing
whitespace stripped; trailing blank rows removed; final newline appended.

No metadata, no escaped characters beyond what the widget actually rendered.
This means snapshot files render legibly on GitHub and are trivial to diff
by eye:

=begin code

┌──────────────┐
│ Hello, Selkie│
└──────────────┘

=end code

=head1 CAVEATS

=item B<Styles aren't captured.> Two widgets that render the same glyphs in different colors produce identical snapshots. If style matters, test it via the widget's attributes directly.
=item B<Non-ASCII width.> Snapshots use one-character-per-cell. Wide characters (CJK, emoji) may render over multiple cells; the captured output reflects what C<ncplane_at_yx> returns at each cell position.
=item B<Real notcurses init.> Each call spins notcurses up and tears it down. ~50-100ms per snapshot. For small test suites this is fine; for large ones, group related snapshots in the same test and share context if performance matters.
=item B<Headless-friendly.> Init is done against a pipe-compatible output, so tests run in CI without a TTY. Output to stderr is silenced during init/stop to avoid the notcurses "signals weren't registered" diagnostic leaking into TAP.

=head1 SEE ALSO

=item L<Selkie::Test::Keys> — simulate events before taking a snapshot
=item L<Selkie::Test::Focus> — focus-gated rendering paths

=end pod

unit module Selkie::Test::Snapshot;

use NativeCall;
use Test;

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Context;
use Notcurses::Native::Channel;

use Selkie::Widget;

#| Marker line that identifies a styled snapshot. The fork-per-scenario
#| harness (C<Selkie::Test::Snapshot::Harness>) detects this on the
#| first line of subprocess stdout and routes the golden file to a
#| separate C<golden-styled/> subdirectory. Plain snapshots without
#| this marker continue to use the existing C<golden/> subdirectory.
constant STYLED-SNAPSHOT-MARKER is export = '=== styled-snapshot v1 ===';

# --- Output redirection for notcurses ------------------------------------
#
# notcurses writes terminal init/restore sequences to the FILE* it's
# given (stdout by default). Under prove6 this corrupts TAP parsing.
# Pass notcurses its own /dev/null FILE* so it writes there instead of
# stdout — fds 1 and 2 are never touched.

sub fopen(Str, Str) returns Pointer is native {*}
sub fclose(Pointer) returns int32 is native {*}
sub fileno(Pointer) returns int32 is native {*}

sub dup(int32 --> int32) is native {*}
sub dup2(int32, int32 --> int32) is native {*}

my Pointer $null-fp;
sub ensure-null-fp(--> Pointer) {
    unless $null-fp {
        $null-fp = fopen('/dev/null', 'w');
    }
    $null-fp;
}

# Redirect fd 1 & 2 to /dev/null at RUNTIME, in every process that
# uses this module. Has to be an INIT phaser — mainline `my $foo =
# dup(1)` at module top level runs during PRECOMPILATION in a child
# process and gets cached; in the consumer process that loads the
# precomp, the expression doesn't re-execute, so our dup2 never
# actually runs in the process we care about. INIT guarantees
# runtime execution in every process.
#
# After this block runs:
#   - fd 1 and fd 2 point at /dev/null; C-level writes (notcurses,
#     libc) go nowhere.
#   - Raku's $*OUT is reopened on a fd-backed path pointing to the
#     SAVED original stdout fd, so Raku-side `print` / `say`
#     (including Test framework TAP emission and render-to-string's
#     output capture by the harness) still reach the original pipe.
my int32 $saved-stdout-fd = -1;

INIT {
    my $null-path = $*KERNEL.name.lc ~~ /win/ ?? 'NUL' !! '/dev/null';

    # Use fopen + fileno rather than open(2) because open() is
    # variadic on macOS (int open(const char*, int, ...)) and Raku's
    # NativeCall can't reliably call variadic functions. fopen
    # returns a FILE*; fileno extracts the underlying fd.
    $saved-stdout-fd = dup(1);
    my Pointer $null-fp = fopen($null-path, 'w');
    if $null-fp.defined {
        my int32 $null-fd = fileno($null-fp);
        if $null-fd >= 0 {
            dup2($null-fd, 1);
            dup2($null-fd, 2);
        }
    }

    my Bool $rerouted = False;
    for "/dev/fd/$saved-stdout-fd", "/proc/self/fd/$saved-stdout-fd" -> $path {
        if $path.IO.e {
            try {
                $*OUT = open($path, :w);
                $rerouted = True;
                last;
            }
        }
    }

    unless $rerouted {
        dup2($saved-stdout-fd, 1);
    }
}

# --- Shared notcurses instance -------------------------------------------
#
# notcurses only allows one init per process — subsequent inits return
# null. So we init lazily on first render and share the handle across
# every render in the same test run. Cleanup on program exit via END.

my $nc-shared;
my Str $saved-tty-state;

sub ensure-nc() {
    return if $nc-shared;


    # fd 1/2 are already redirected to /dev/null from module load
    # (see top-level block above). Anything notcurses writes via C
    # (including stop's "signals weren't registered" warnings) lands
    # in /dev/null; $*OUT is rerouted to the original stdout.

    # Snapshot /dev/tty termios state BEFORE notcurses_init so we can
    # restore it on process exit as a belt-and-suspenders layer in
    # case notcurses_stop misses something.
    if '/dev/tty'.IO.e {
        # Shell redirect from /dev/tty so stty operates on the real
        # terminal. Raku's run doesn't interpret :in(Str) as a path
        # redirect — use shell instead. qx{...} captures stdout.
        my $g = try qx{stty -g < /dev/tty 2>/dev/null} // '';
        $saved-tty-state = $g.chomp if $g.chars > 0;
    }

    # Give notcurses its own /dev/null FILE* to write into, so its
    # terminal init/restore sequences never reach stdout and never
    # interfere with TAP output.
    my $fp = ensure-null-fp();

    # Let notcurses install its signal handlers. Without them,
    # notcurses_stop's drop_signals() detects that signal_nc was never
    # set and emits "signals weren't registered for ..." to stderr —
    # leaks into TAP even with fd 2 redirected, because the message
    # goes via libnotcurses's own stderr-equivalent reference that
    # was established before our dup2. With handlers enabled, stop
    # unregisters them cleanly and the warning doesn't fire.
    #
    # NCOPTION_NO_WINCH_SIGHANDLER stays off because we poll for
    # resize ourselves (see Selkie::App).
    my $flags = NCOPTION_SUPPRESS_BANNERS
            +| NCOPTION_NO_ALTERNATE_SCREEN
            +| NCOPTION_NO_WINCH_SIGHANDLER;
    my $opts = NotcursesOptions.new(:$flags, loglevel => NCLOGLEVEL_SILENT);
    $nc-shared = notcurses_init($opts, $fp);

    unless $nc-shared {
        die "notcurses_init failed (it can only succeed once per process)";
    }
}

END {
    # Restore the terminal on process exit. Redirect fd 1/2 to
    # /dev/null IMMEDIATELY before calling notcurses_stop so any
    # stderr it emits (warnings about signal handlers it thinks
    # weren't registered, etc.) lands in /dev/null rather than the
    # TAP stream. Doing this at END rather than INIT/module-load
    # because Raku's precomp-and-cache semantics mean top-level
    # side effects can get baked into the precomp artifact and
    # never re-run in consumer processes.
    if $nc-shared {
        my $null-path = $*KERNEL.name.lc ~~ /win/ ?? 'NUL' !! '/dev/null';
        my Pointer $null-fp = fopen($null-path, 'w');
        if $null-fp.defined {
            my int32 $null-fd = fileno($null-fp);
            if $null-fd >= 0 {
                dup2($null-fd, 1);
                dup2($null-fd, 2);
            }
        }
        notcurses_stop($nc-shared);
        $nc-shared = Nil;
    }

    # Belt-and-suspenders: restore /dev/tty termios via stty in case
    # notcurses_stop missed anything or didn't run (init failed
    # before $nc-shared was assigned). Best-effort — errors swallowed.
    if $saved-tty-state && '/dev/tty'.IO.e {
        try shell "stty '$saved-tty-state' < /dev/tty 2>/dev/null";
    }
}

# Terminal-restore on END is handled by notcurses_stop. That's
# feasible because ensure-fd-redirect (above) redirects fd 1 & 2 to
# /dev/null before notcurses_init runs — so notcurses's C-level
# writes (display resets, "signals weren't registered" warnings, etc)
# can't leak into prove6's TAP pipe. Raku code that prints via
# $*OUT still reaches the original stdout via a fd-backed reroute.
#
# Skipping stop would leave Kitty keyboard protocol pushed and mouse/
# bracketed-paste protocols enabled — after a test run the parent
# terminal couldn't accept Ctrl+C as SIGINT (Kitty kbd transmitted
# it as an escape sequence) and Enter arrived as ^M (ICRNL off).
#
# Plus a stty-based termios restore in the END phaser as a
# belt-and-suspenders layer.

# --- Rendering ------------------------------------------------------------

#|( Render a widget to a plain-text string via a shared headless notcurses
    instance. Returns the rendered cells row-by-row, joined with newlines.
    Trailing whitespace on each line is stripped, and trailing blank
    lines are removed.

    The widget is given its own plane as a child of the stdplane, sized
    to C<$rows> × C<$cols>. Containers that manage child planes in their
    C<render> work correctly — the standard mount path is exercised.

    The notcurses instance persists across calls within a test process
    (init is once-per-process). The widget's plane is destroyed after
    each call so renders don't leak.

    Pass C<:capture-styles> to emit the style-aware format instead of
    the plain glyph grid — see L<Selkie::Test::Snapshot> Pod6 for the
    format spec. The harness routes styled goldens to
    C<golden-styled/> automatically. )
sub render-to-string(Selkie::Widget $widget,
                     UInt :$rows = 24,
                     UInt :$cols = 80,
                     Bool :$capture-styles = False,
                     --> Str
) is export {
    ensure-nc();

    my $stdplane = notcurses_stdplane($nc-shared);
    # Resize stdplane to target dimensions and clear it so leftover content
    # from a previous render doesn't bleed through.
    ncplane_resize_simple($stdplane, $rows, $cols);
    ncplane_erase($stdplane);

    # Mount the widget as a child of stdplane (same code path as
    # Selkie::App.add-screen), then set its viewport + render.
    $widget.init-plane($stdplane, y => 0, x => 0, :$rows, :$cols);
    $widget.set-viewport(abs-y => 0, abs-x => 0, :$rows, :$cols);
    $widget.render;

    # Composite the pile. Container widgets render their children onto
    # separate subplanes — individual planes only show what was drawn
    # directly on them, never their descendants. notcurses_render
    # flattens everything into the internal "last frame" buffer. The
    # actual terminal write lands on /dev/null (see ensure-nc) so
    # stdout is untouched. notcurses_at_yx then reads cells from the
    # rendered-frame buffer — the composited view we want.
    notcurses_render($nc-shared);

    my $result = $capture-styles
        ?? styled-readback($rows, $cols)
        !! plain-readback($rows, $cols);

    # Destroy the widget's plane so the next render gets a fresh one.
    # The shared notcurses instance lives on.
    $widget.destroy;

    $result;
}

# Plain readback — character-only grid; existing v1 behaviour. Trailing
# whitespace per row stripped; trailing blank rows dropped.
sub plain-readback(UInt $rows, UInt $cols --> Str) {
    my @lines;
    for ^$rows -> $y {
        my $line = '';
        for ^$cols -> $x {
            my uint16 $stylemask = 0;
            my uint64 $channels = 0;
            my $egc = notcurses_at_yx($nc-shared, $y, $x,
                                      $stylemask, $channels);
            $line ~= ($egc && $egc.chars ?? $egc !! ' ');
        }
        @lines.push($line.trim-trailing);
    }
    while @lines && @lines[*-1] eq '' {
        @lines.pop;
    }
    @lines.join("\n");
}

# Styled readback — emits the marker, a glyphs block, a parallel styles
# block, and a legend. Each cell is keyed by its (fg-rgb, bg-rgb,
# stylemask) tuple. The default tuple (no fg, no bg, no styles) gets
# '.'; subsequent tuples get A-Z, a-z, 0-9 in first-seen order.
#
# Trailing-blank trimming: a row is "blank" iff its glyph row is all
# spaces AND its styles row is all '.'. The two rows are trimmed
# in lockstep so they stay aligned in the output.
sub styled-readback(UInt $rows, UInt $cols --> Str) {
    my @glyph-rows;
    my @style-rows;
    my %tuple-to-key{Str} = '__default__' => '.';
    my @tuple-order;        # tuples in first-seen order, for legend
    my @letters = flat ('A'..'Z'), ('a'..'z'), ('0'..'9');
    my $next-letter = 0;

    for ^$rows -> $y {
        my $glyph-line = '';
        my $style-line = '';
        for ^$cols -> $x {
            my uint16 $stylemask = 0;
            my uint64 $channels = 0;
            my $egc = notcurses_at_yx($nc-shared, $y, $x,
                                      $stylemask, $channels);
            my $glyph = ($egc && $egc.chars ?? $egc !! ' ');

            my $fg-default = ?ncchannels_fg_default_p($channels);
            my $bg-default = ?ncchannels_bg_default_p($channels);
            my $fg-rgb = $fg-default ?? -1 !! ncchannels_fg_rgb($channels).Int;
            my $bg-rgb = $bg-default ?? -1 !! ncchannels_bg_rgb($channels).Int;
            my $sm     = $stylemask.Int;

            my $tuple-key = ($fg-default && $bg-default && $sm == 0)
                ?? '__default__'
                !! "$fg-rgb|$bg-rgb|$sm";

            unless %tuple-to-key{$tuple-key}:exists {
                if $next-letter >= @letters.elems {
                    die "styled-snapshot: more than {@letters.elems} unique"
                        ~ " styles in render — extend the alphabet or"
                        ~ " split the snapshot";
                }
                %tuple-to-key{$tuple-key} = @letters[$next-letter++];
                @tuple-order.push($tuple-key);
            }

            $glyph-line ~= $glyph;
            $style-line ~= %tuple-to-key{$tuple-key};
        }
        @glyph-rows.push($glyph-line);
        @style-rows.push($style-line);
    }

    # Lockstep trim trailing blank rows.
    while @glyph-rows
            && @glyph-rows[*-1] ~~ /^ ' '* $/
            && @style-rows[*-1] ~~ /^ '.'* $/ {
        @glyph-rows.pop;
        @style-rows.pop;
    }

    # Per-row trim: cut both glyph and style rows to the same trimmed
    # length so they stay aligned. Use the glyph row's trim length as
    # canonical (style cells corresponding to trailing spaces are
    # always '.' — they wouldn't be trimmed if a non-default style
    # were set there).
    for ^@glyph-rows.elems -> $i {
        my $trimmed = @glyph-rows[$i].trim-trailing;
        my $len = $trimmed.chars;
        @glyph-rows[$i] = $trimmed;
        @style-rows[$i] = @style-rows[$i].substr(0, $len);
    }

    my @legend = ('.: (default)',);
    for @tuple-order -> $tk {
        next if $tk eq '__default__';
        @legend.push(%tuple-to-key{$tk} ~ ': ' ~ describe-tuple($tk));
    }

    join("\n",
        STYLED-SNAPSHOT-MARKER,
        '--- glyphs ---',
        |@glyph-rows,
        '--- styles ---',
        |@style-rows,
        '--- legend ---',
        |@legend,
    );
}

# Format a tuple key (fg|bg|stylemask) as a human-readable description.
# fg/bg of -1 mean "default / inherited" and are omitted; stylemask of
# 0 is omitted.
sub describe-tuple(Str $tk --> Str) {
    my ($fg, $bg, $sm) = $tk.split('|').map(*.Int);
    my @parts;
    @parts.push: sprintf('fg=#%06X', $fg) unless $fg == -1;
    @parts.push: sprintf('bg=#%06X', $bg) unless $bg == -1;
    if $sm != 0 {
        my @flags;
        @flags.push: 'BOLD'      if $sm +& NCSTYLE_BOLD;
        @flags.push: 'ITALIC'    if $sm +& NCSTYLE_ITALIC;
        @flags.push: 'UNDERLINE' if $sm +& NCSTYLE_UNDERLINE;
        @flags.push: 'STRUCK'    if $sm +& NCSTYLE_STRUCK;
        @parts.push: 'styles=' ~ @flags.join('|') if @flags;
    }
    @parts ?? @parts.join(' ') !! '(default)';
}

# --- Snapshot comparison --------------------------------------------------

#|( Test assertion: render the widget to C<$rows> × C<$cols> and compare
    against a stored snapshot file.

    =item First run or missing file: the snapshot is created and the test passes.
    =item Matching output: the test passes.
    =item Differing output: the test fails and a unified-ish diff is printed as TAP diagnostics.

    Set the env var C<SELKIE_UPDATE_SNAPSHOTS> to a truthy value to
    overwrite existing snapshots with current output.

    The snapshot directory defaults to C<t/snapshots>. With
    C<:capture-styles> the directory is automatically suffixed with
    C<-styled> (default: C<t/snapshots-styled>) so plain and styled
    goldens never collide. Override C<$dir> for a custom location;
    when overriding alongside C<:capture-styles>, suffix C<$dir>
    yourself. The directory is auto-created on first use. )
sub snapshot-ok(Selkie::Widget $widget,
                Str:D $name,
                UInt :$rows = 24,
                UInt :$cols = 80,
                Bool :$capture-styles = False,
                Str  :$dir is copy
) is export {
    without $dir {
        $dir = $capture-styles ?? 't/snapshots-styled' !! 't/snapshots';
    }
    my $snap = $dir.IO.add("$name.snap");
    my $rendered = render-to-string($widget, :$rows, :$cols, :$capture-styles);

    mkdir $dir unless $dir.IO.d;

    my $update = so %*ENV<SELKIE_UPDATE_SNAPSHOTS>;

    if !$snap.e {
        $snap.spurt($rendered ~ "\n");
        pass "snapshot '$name' created";
        return;
    }

    if $update {
        $snap.spurt($rendered ~ "\n");
        pass "snapshot '$name' updated";
        return;
    }

    my $expected = $snap.slurp.chomp;
    if $rendered eq $expected {
        pass "snapshot '$name' matches";
    } else {
        flunk "snapshot '$name' differs";
        diag "  expected → got (first difference):";
        for diff-lines($expected, $rendered) -> $line {
            diag "  $line";
        }
        diag "  (set SELKIE_UPDATE_SNAPSHOTS=1 to accept new output)";
    }
}

# Minimal line-by-line diff. Prefix — for expected-only, + for got-only,
# = for identical. Doesn't align hunks — adequate for small widget snapshots.
sub diff-lines(Str $expected, Str $got --> List) {
    my @exp = $expected.lines;
    my @got = $got.lines;
    my @out;
    my $max = @exp.elems max @got.elems;
    for ^$max -> $i {
        my $e = @exp[$i] // '';
        my $g = @got[$i] // '';
        if $e eq $g {
            @out.push("  = $e");
        } else {
            @out.push("  - $e");
            @out.push("  + $g");
        }
    }
    @out.List;
}
