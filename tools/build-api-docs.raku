#!/usr/bin/env raku
#
# build-api-docs.raku — regenerate docs/api/*.md from every module in lib/
#
# Each lib/Foo/Bar.rakumod becomes docs/api/Foo--Bar.md (:: flattened so the
# filesystem stays portable). A docs/api/index.md is produced with a sorted
# link table.
#
# Usage:
#   raku tools/build-api-docs.raku
#
# The script expects to be run from the Selkie project root.

use v6.d;

# --- Inline formatting code cleanup ---
# Pod::To::Markdown renders =begin pod blocks fully but leaves declarator
# comment text with raw formatting codes (C<>, L<>, B<>, I<>). Convert to
# Markdown equivalents here.

sub fixup-inline-codes(Str $md --> Str) {
    my $result = $md;

    # C<foo> → `foo` (inline code). Non-greedy, no nested C<>.
    $result ~~ s:g/ 'C<' ( <-[<>]>+? ) '>' /`$0`/;

    # B<foo> → **foo** (bold).
    $result ~~ s:g/ 'B<' ( <-[<>]>+? ) '>' /**$0**/;

    # I<foo> → *foo* (italic).
    $result ~~ s:g/ 'I<' ( <-[<>]>+? ) '>' /*$0*/;

    # L<Selkie::Foo::Bar> → [Selkie::Foo::Bar](Selkie--Foo--Bar.md).
    $result = $result.subst(
        / 'L<' ( 'Selkie' <[:\w]>+ ) '>' /,
        -> $m {
            my $target = $m[0].Str;
            my $slug = $target.subst('::', '--', :g);
            "[$target]($slug.md)";
        },
        :g,
    );
    # Other L<> targets are left as bare text.
    $result ~~ s:g/ 'L<' ( <-[<>]>+? ) '>' /$0/;

    # Pod::To::Markdown renders =begin pod L<Selkie::Foo::Bar> as
    # [Selkie::Foo::Bar](Selkie::Foo::Bar) — same text on both sides.
    # Slugify the URL part so the link actually resolves in docs/api/.
    $result = $result.subst(
        / '[' ( 'Selkie' <[:\w]>+ ) '](' ( 'Selkie' <[:\w]>+ ) ')' /,
        -> $m {
            my $label = $m[0].Str;
            my $slug  = $m[1].Str.subst('::', '--', :g);
            "[$label]($slug.md)";
        },
        :g,
    );

    $result;
}

my IO::Path $lib-root  = 'lib'.IO;
my IO::Path $docs-root = 'docs/api'.IO;

die "Run me from the Selkie project root (couldn't find $lib-root)" unless $lib-root.d;
mkdir $docs-root unless $docs-root.d;

# Collect every *.rakumod file under lib/
my @module-files = gather {
    sub walk(IO::Path $dir) {
        for $dir.dir -> $entry {
            if $entry.d {
                walk($entry);
            } elsif $entry.f && $entry.extension eq 'rakumod' {
                take $entry;
            }
        }
    }
    walk($lib-root);
};

my @generated;

for @module-files.sort -> $src {
    my $rel     = $src.relative($lib-root);
    my $mod     = $rel.subst(/ '.rakumod' $ /, '').subst('/', '::', :g);
    my $outname = $rel.subst(/ '.rakumod' $ /, '.md').subst('/', '--', :g);
    my $out     = $docs-root.add($outname);

    # Shell out to raku --doc=Markdown to get the rendered output. This
    # path exercises Pod::To::Markdown which already handles declarator
    # blocks and =begin pod blocks cleanly. -I lib is required so that
    # modules which import other modules from this same distribution
    # (before install) can still resolve.
    my $proc = run 'raku', '-I', 'lib', '--doc=Markdown', $src.Str, :out, :err;
    my $md = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);

    if $proc.exitcode != 0 || $md.chars == 0 {
        note "! $mod: empty or failed ({$err.lines.head // ''})";
        next;
    }

    # Post-process: Pod::To::Markdown expands inline formatting codes
    # (C<>, L<>, B<>, I<>) inside =begin pod blocks but NOT inside
    # declarator comments (#| and #=). Those arrive in the output as
    # literal text. Convert them here so the final Markdown is clean
    # regardless of where the source text lived.
    $md = fixup-inline-codes($md);

    # Prepend a machine-readable title if the Pod doesn't already have an H1
    my $has-h1 = $md ~~ /^^ '# ' || ^^ .+ \n '=' +/;
    unless $has-h1 {
        $md = "# $mod\n\n" ~ $md;
    }

    $out.spurt($md);
    @generated.push({ :$mod, :file($outname) });
    say "  {$mod.fmt('%-40s')} → docs/api/$outname";
}

# Build an index page, grouped by category.
#
# Classification rules:
#   - Selkie::Layout::* — layouts
#   - Selkie::Widget::*RichText::Span — under display widgets
#   - Selkie::Widget::{Text,RichText,TextStream,Image,ProgressBar,Spinner} — display
#   - Selkie::Widget::{TextInput,MultiLineInput,Button,Checkbox,RadioGroup,Select} — input
#   - Selkie::Widget::{ListView,CardList,ScrollView,Table} — lists / data
#   - Selkie::Widget::{Border,Modal,ConfirmModal,FileBrowser,Toast,TabBar,CommandPalette} — chrome / overlays
#   - Core: Selkie, Selkie::App, Selkie::Widget, Selkie::Container, Selkie::Store, Selkie::ScreenManager, Selkie::Event, Selkie::Sizing, Selkie::Style, Selkie::Theme
#
# Anything that doesn't match falls into "Other".

my %categories =
    'Core'               => <Selkie Selkie::App Selkie::Widget Selkie::Container Selkie::Store Selkie::ScreenManager Selkie::Event Selkie::Sizing Selkie::Style Selkie::Theme>,
    'Layouts'            => <Selkie::Layout::VBox Selkie::Layout::HBox Selkie::Layout::Split>,
    'Display widgets'    => <Selkie::Widget::Text Selkie::Widget::RichText Selkie::Widget::RichText::Span Selkie::Widget::TextStream Selkie::Widget::Image Selkie::Widget::ProgressBar Selkie::Widget::Spinner>,
    'Input widgets'      => <Selkie::Widget::TextInput Selkie::Widget::MultiLineInput Selkie::Widget::Button Selkie::Widget::Checkbox Selkie::Widget::RadioGroup Selkie::Widget::Select>,
    'List widgets'       => <Selkie::Widget::ListView Selkie::Widget::CardList Selkie::Widget::ScrollView Selkie::Widget::Table>,
    'Chrome / overlays'  => <Selkie::Widget::Border Selkie::Widget::Modal Selkie::Widget::ConfirmModal Selkie::Widget::FileBrowser Selkie::Widget::Toast Selkie::Widget::TabBar Selkie::Widget::CommandPalette>,
    'Test helpers'       => <Selkie::Test::Keys Selkie::Test::Supply Selkie::Test::Store Selkie::Test::Focus Selkie::Test::Tree Selkie::Test::Snapshot>,
;

# Preferred section ordering for the index
my @section-order = (
    'Core',
    'Layouts',
    'Display widgets',
    'Input widgets',
    'List widgets',
    'Chrome / overlays',
    'Test helpers',
    'Other',
);

# Build a name → file lookup
my %by-name;
for @generated -> $entry {
    %by-name{$entry<mod>} = $entry<file>;
}

# Partition generated docs into sections
my %sections;
my @all-names = @generated.map(*.<mod>);
my %seen;
for %categories.kv -> $section, @names {
    for @names -> $name {
        if %by-name{$name}:exists {
            %sections{$section}.push({ :mod($name), :file(%by-name{$name}) });
            %seen{$name} = True;
        }
    }
}
# Anything not yet seen goes into "Other"
for @generated -> $entry {
    unless %seen{$entry<mod>} {
        %sections<Other>.push($entry);
    }
}

my $index-path = $docs-root.add('index.md');
my $index = "# Selkie API reference\n\n"
          ~ "Auto-generated from Pod6 declarator comments and pod blocks "
          ~ "in each module. See the main [Readme](../../README.md) for "
          ~ "narrative docs, synopsis examples, and design philosophy.\n\n";

for @section-order -> $section {
    next unless %sections{$section}:exists && %sections{$section}.elems > 0;
    $index ~= "## $section\n\n";
    for %sections{$section}.list -> $entry {
        $index ~= "- [{$entry<mod>}]({$entry<file>})\n";
    }
    $index ~= "\n";
}

$index-path.spurt($index);
say "\nWrote index: $index-path";
say "Generated {@generated.elems} API doc files.";
