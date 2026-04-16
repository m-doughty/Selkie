=begin pod

=head1 NAME

Selkie::Test::Snapshot::Harness - Fork-per-scenario snapshot runner

=head1 SYNOPSIS

In your app's C<xt/02-snapshots.rakutest>:

=begin code :lang<raku>

use Test;
use lib 'lib';
use Selkie::Test::Snapshot::Harness;

run-snapshots;

=end code

That's the entire harness. Drop scenario scripts into C<xt/snapshots/>,
each one self-contained:

=begin code :lang<raku>

# xt/snapshots/01-my-widget.raku
use lib 'lib';
use Selkie::Test::Snapshot;
use My::App::Widget;

my $w = My::App::Widget.new(...);
print render-to-string($w, rows => 10, cols => 40);

=end code

=head1 DESCRIPTION

Fork-per-scenario harness for widget snapshot testing. Each
C<.raku> file in the scenarios directory runs in its own subprocess.
The harness captures stdout, normalises it (trim trailing whitespace,
drop trailing blank rows), and compares against a golden file under
C<golden/>.

B<Subprocess isolation matters.> There's a MoarVM specializer bug that
intermittently crashes ("Spesh: releasing temp not in use") during
rendering patterns involving NativeCall + nested widget planes. Per-
scenario subprocesses give each render a cold spesh state. The harness
additionally sets C<MVM_SPESH_DISABLE=1> in the subprocess environment
to eliminate the risk entirely — marginally slower, fully reliable.

When upstream MoarVM fixes the spesh bug we can drop C<MVM_SPESH_DISABLE>
but keep the subprocess isolation, since it's also useful for widget-
test independence in general.

=head1 WORKFLOW

=item First run / missing C<.snap>: golden file is created, test passes.
=item Matching output: test passes silently.
=item Mismatch: test fails with a unified-ish diff in TAP diagnostics.
=item C<SELKIE_UPDATE_SNAPSHOTS=1>: overwrite every golden file.

=head1 ARGUMENTS

C<run-snapshots> accepts named args:

=item C<:snap-dir('xt/snapshots')> — directory containing scenario scripts
=item C<:golden-subdir('golden')> — subdirectory of C<snap-dir> for goldens
=item C<:styled-golden-subdir('golden-styled')> — subdirectory for styled goldens; the harness routes scenarios that emit the C<=== styled-snapshot v1 ===> marker (via L<Selkie::Test::Snapshot>'s C<:capture-styles> mode) here automatically
=item C<:raku-args> — extra C<-I> flags for the subprocess (defaults to C<-I lib>)
=item C<:disable-spesh(True)> — set C<MVM_SPESH_DISABLE=1>. Set to False if you want to test with spesh enabled, but expect flakes.

=head1 STYLED SCENARIOS

Plain and styled scenarios can live in the same C<xt/snapshots/> dir.
The harness reads each subprocess's stdout, peeks at the first line,
and routes to C<golden/> or C<golden-styled/> accordingly. No
configuration is needed in scenario scripts beyond passing
C<:capture-styles> to C<render-to-string>:

=begin code :lang<raku>

# xt/snapshots/24-heatmap-styled.raku
use lib 'lib';
use Selkie::Test::Snapshot;
use My::Heatmap;

print render-to-string(My::Heatmap.new(...), :rows(8), :cols(20), :capture-styles);

=end code

=end pod

unit module Selkie::Test::Snapshot::Harness;

use Test;

# Marker that identifies a styled snapshot. Kept inline rather than
# imported from Selkie::Test::Snapshot to avoid loading notcurses in
# the harness process — the harness is the test driver, not a
# rendering consumer.
constant STYLED-MARKER = '=== styled-snapshot v1 ===';

#|( Run every C<*.raku> file in C<$snap-dir> as an isolated subprocess,
    capture stdout, and snapshot-test it against
    C<{$snap-dir}/{$golden-subdir}/{name}.snap> (plain) or
    C<{$snap-dir}/{$styled-golden-subdir}/{name}.snap> (styled, when the
    scenario emits the C<=== styled-snapshot v1 ===> marker).

    Emits one TAP assertion per scenario. Call this from an xt/
    rakutest file — nothing else needed. )
sub run-snapshots(
    IO() :$snap-dir              = 'xt/snapshots',
    Str  :$golden-subdir         = 'golden',
    Str  :$styled-golden-subdir  = 'golden-styled',
         :@raku-args             = <-I lib>,
    Bool :$disable-spesh         = True,
) is export {
    my $dir = $snap-dir.IO;
    my $golden-dir         = $dir.add($golden-subdir);
    my $styled-golden-dir  = $dir.add($styled-golden-subdir);
    $golden-dir.mkdir         unless $golden-dir.d;
    $styled-golden-dir.mkdir  unless $styled-golden-dir.d;

    my @scenarios = $dir.dir(test => /\.raku$/).sort(*.basename);
    unless @scenarios {
        plan 1;
        flunk "no scenarios found in $dir";
        done-testing;
        return;
    }

    plan @scenarios.elems;

    my $update = so %*ENV<SELKIE_UPDATE_SNAPSHOTS>;

    # MVM_SPESH_DISABLE must be set before MoarVM starts, so we set it
    # on the subprocess env rather than in the module's BEGIN.
    my %env = %*ENV;
    %env<MVM_SPESH_DISABLE> = '1' if $disable-spesh;

    for @scenarios -> $script {
        my $name = $script.basename.subst(/\.raku$/, '');

        my $proc = run 'raku', |@raku-args, $script.Str, :out, :err, :%env;
        my $stdout = $proc.out.slurp(:close);
        my $stderr = $proc.err.slurp(:close);
        my $exit   = $proc.exitcode;

        if $exit != 0 {
            flunk "snapshot '$name' — scenario exited $exit";
            diag "  stdout: {$stdout.substr(0, 400)}";
            diag "  stderr: $stderr" if $stderr;
            next;
        }

        # Detect styled scenarios by their first-line marker. Routing
        # is automatic — scenario scripts don't need to know which
        # subdir their golden lives in. Empty stdout (e.g. a widget
        # that legitimately renders blank) is never styled.
        my $first-line = $stdout.lines.head // '';
        my $is-styled  = $first-line eq STYLED-MARKER;
        my $rendered  = $is-styled
            ?? normalise-styled($stdout)
            !! normalise($stdout);
        my $golden    = ($is-styled ?? $styled-golden-dir !! $golden-dir).add("$name.snap");

        if !$golden.e {
            $golden.spurt($rendered ~ "\n");
            pass "snapshot '$name' created" ~ ($is-styled ?? ' (styled)' !! '');
            next;
        }

        if $update {
            $golden.spurt($rendered ~ "\n");
            pass "snapshot '$name' updated" ~ ($is-styled ?? ' (styled)' !! '');
            next;
        }

        my $expected = $golden.slurp.chomp;
        if $rendered eq $expected {
            pass "snapshot '$name'" ~ ($is-styled ?? ' (styled)' !! '');
        } else {
            flunk "snapshot '$name' differs from {$golden.Str}";
            diag "  expected ({$expected.lines.elems} lines) → got ({$rendered.lines.elems} lines):";
            for diff-lines($expected, $rendered) -> $ln { diag "  $ln" }
            diag "  (set SELKIE_UPDATE_SNAPSHOTS=1 to accept new output)";
            diag "  (rerun standalone: MVM_SPESH_DISABLE=1 raku {@raku-args.join(' ')} {$script.Str})";
        }
    }

    done-testing;
}

sub normalise(Str $s --> Str) {
    my @lines = $s.lines.map(*.trim-trailing);
    while @lines && @lines[*-1] eq '' { @lines.pop }
    @lines.join("\n");
}

# Styled output is emitted by Selkie::Test::Snapshot::render-to-string
# already trim-friendly (it does its own lockstep trim). We just chomp
# the trailing newline if any so byte-for-byte comparison works after
# spurt-with-newline.
sub normalise-styled(Str $s --> Str) {
    $s.chomp;
}

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
