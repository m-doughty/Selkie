NAME
====

Selkie::Test::Snapshot::Harness - Fork-per-scenario snapshot runner

SYNOPSIS
========

In your app's `xt/02-snapshots.rakutest`:

```raku
use Test;
use lib 'lib';
use Selkie::Test::Snapshot::Harness;

run-snapshots;
```

That's the entire harness. Drop scenario scripts into `xt/snapshots/`, each one self-contained:

```raku
# xt/snapshots/01-my-widget.raku
use lib 'lib';
use Selkie::Test::Snapshot;
use My::App::Widget;

my $w = My::App::Widget.new(...);
print render-to-string($w, rows => 10, cols => 40);
```

DESCRIPTION
===========

Fork-per-scenario harness for widget snapshot testing. Each `.raku` file in the scenarios directory runs in its own subprocess. The harness captures stdout, normalises it (trim trailing whitespace, drop trailing blank rows), and compares against a golden file under `golden/`.

**Subprocess isolation matters.** There's a MoarVM specializer bug that intermittently crashes ("Spesh: releasing temp not in use") during rendering patterns involving NativeCall + nested widget planes. Per- scenario subprocesses give each render a cold spesh state. The harness additionally sets `MVM_SPESH_DISABLE=1` in the subprocess environment to eliminate the risk entirely — marginally slower, fully reliable.

When upstream MoarVM fixes the spesh bug we can drop `MVM_SPESH_DISABLE` but keep the subprocess isolation, since it's also useful for widget- test independence in general.

WORKFLOW
========

  * First run / missing `.snap`: golden file is created, test passes.

  * Matching output: test passes silently.

  * Mismatch: test fails with a unified-ish diff in TAP diagnostics.

  * `SELKIE_UPDATE_SNAPSHOTS=1`: overwrite every golden file.

ARGUMENTS
=========

`run-snapshots` accepts named args:

  * `:snap-dir('xt/snapshots')` — directory containing scenario scripts

  * `:golden-subdir('golden')` — subdirectory of `snap-dir` for goldens

  * `:styled-golden-subdir('golden-styled')` — subdirectory for styled goldens; the harness routes scenarios that emit the `=== styled-snapshot v1 ===` marker (via [Selkie::Test::Snapshot](Selkie--Test--Snapshot.md)'s `:capture-styles` mode) here automatically

  * `:raku-args` — extra `-I` flags for the subprocess (defaults to `-I lib`)

  * `:disable-spesh(True)` — set `MVM_SPESH_DISABLE=1`. Set to False if you want to test with spesh enabled, but expect flakes.

STYLED SCENARIOS
================

Plain and styled scenarios can live in the same `xt/snapshots/` dir. The harness reads each subprocess's stdout, peeks at the first line, and routes to `golden/` or `golden-styled/` accordingly. No configuration is needed in scenario scripts beyond passing `:capture-styles` to `render-to-string`:

```raku
# xt/snapshots/24-heatmap-styled.raku
use lib 'lib';
use Selkie::Test::Snapshot;
use My::Heatmap;

print render-to-string(My::Heatmap.new(...), :rows(8), :cols(20), :capture-styles);
```

### sub run-snapshots

```raku
sub run-snapshots(
    IO(Any) :$snap-dir = "xt/snapshots",
    Str :$golden-subdir = "golden",
    Str :$styled-golden-subdir = "golden-styled",
    :@raku-args = Code.new,
    Bool :$disable-spesh = Bool::True
) returns Mu
```

Run every `*.raku` file in `$snap-dir` as an isolated subprocess, capture stdout, and snapshot-test it against `{$snap-dir}/{$golden-subdir}/{name}.snap` (plain) or `{$snap-dir}/{$styled-golden-subdir}/{name}.snap` (styled, when the scenario emits the `=== styled-snapshot v1 ===` marker). Emits one TAP assertion per scenario. Call this from an xt/ rakutest file — nothing else needed.

