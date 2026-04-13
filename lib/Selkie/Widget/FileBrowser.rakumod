=begin pod

=head1 NAME

Selkie::Widget::FileBrowser - Shell-style file picker modal

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::FileBrowser;

my $browser = Selkie::Widget::FileBrowser.new;
my $modal = $browser.build(
    extensions    => <png jpg json>,
    show-dotfiles => False,
    width-ratio   => 0.7,
    height-ratio  => 0.7,
);

$browser.on-select.tap: -> Str $path {
    $app.close-modal;
    $app.store.dispatch('file/open', :$path);
};

$app.show-modal($modal);
$app.focus($browser.focusable-widget);

=end code

=head1 DESCRIPTION

A modal file picker built on top of C<Modal>, C<ListView>, and
C<TextInput>. Behaves like a shell prompt:

=item The path input shows the current directory + filename prefix
=item Typing filters the list below to matching entries
=item C<Tab> autocompletes to the longest common prefix
=item C<Enter> on a directory descends into it; on a file selects it
=item C<Up>/C<Down> navigate the list
=item C<Esc> cancels without selecting

Extension filtering is optional — pass C<extensions => ()> or omit to
show everything. Hidden files (C<.name>) are excluded unless
C<show-dotfiles> is True.

=head1 EXAMPLES

=head2 Import dialog

=begin code :lang<raku>

sub show-import-dialog() {
    my $browser = Selkie::Widget::FileBrowser.new;
    my $modal = $browser.build(extensions => <png json>);

    $browser.on-select.tap: -> Str $path {
        $app.close-modal;
        import-character($path);
    };

    $app.show-modal($modal);
    $app.focus($browser.focusable-widget);
}

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Modal> — underlying dialog

=end pod

use Selkie::Widget::Modal;
use Selkie::Widget::ListView;
use Selkie::Widget::TextInput;
use Selkie::Widget::Text;
use Selkie::Layout::VBox;
use Selkie::Sizing;
use Selkie::Style;

unit class Selkie::Widget::FileBrowser;

has Selkie::Widget::Modal $.modal;
has Selkie::Widget::ListView $!list;
has Selkie::Widget::TextInput $!path-input;
has IO::Path $!current-dir;
has @!valid-extensions;
has Bool $!show-dotfiles;
has @!dir-entries;     # unfiltered entries for current directory
has Supplier $!select-supplier = Supplier.new;

method on-select(--> Supply) { $!select-supplier.Supply }

method build(
    Str :$start-dir = $*HOME.Str,
    :@extensions,
    Bool :$show-dotfiles = False,
    Rat :$width-ratio = 0.6,
    Rat :$height-ratio = 0.7,
    --> Selkie::Widget::Modal
) {
    @!valid-extensions = @extensions;
    $!show-dotfiles = $show-dotfiles;
    $!current-dir = $start-dir.IO.resolve;

    $!modal = Selkie::Widget::Modal.new(:$width-ratio, :$height-ratio);
    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    $content.add: Selkie::Widget::Text.new(
        text   => 'Select a file',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    );

    $!path-input = Selkie::Widget::TextInput.new(sizing => Sizing.fixed(1));
    $content.add($!path-input);

    $!list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
    $content.add($!list);

    $content.add: Selkie::Widget::Text.new(
        text   => 'Tab: complete · Enter: select · Esc: cancel',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x606080),
    );

    $!modal.set-content($content);

    # Set initial text and load directory
    self!load-dir-entries;
    $!path-input.set-text($!current-dir.Str ~ '/');

    # Every keystroke — parse path, maybe change dir, filter
    $!path-input.on-change.tap: -> $text {
        self!on-text-changed($text);
    };

    # Enter — activate highlighted entry
    $!path-input.on-submit.tap: -> $text {
        self!on-enter;
    };

    # Tab — autocomplete
    $!path-input.on-key: 'tab', -> $ {
        self!on-tab;
    };

    # Up/Down navigate the list
    $!path-input.on-key: 'up', -> $ {
        $!list.select-index($!list.cursor - 1) if $!list.cursor > 0;
    };
    $!path-input.on-key: 'down', -> $ {
        $!list.select-index($!list.cursor + 1) if $!list.cursor < $!list.items.elems - 1;
    };

    $!list.on-activate.tap: -> $name { self!activate-name($name) };

    $!modal;
}

method focusable-widget(--> Selkie::Widget::TextInput) { $!path-input }
method list(--> Selkie::Widget::ListView) { $!list }
method path-input(--> Selkie::Widget::TextInput) { $!path-input }

# --- Internal ---

# Parse text into (directory, filter). Everything up to the last / is directory.
method !parse-text(Str $text --> List) {
    my $expanded = $text.subst(/^ '~'/, $*HOME.Str);
    my $idx = $expanded.rindex('/');
    if $idx.defined {
        my $dir    = $expanded.substr(0, $idx) || '/';
        my $filter = $expanded.substr($idx + 1);
        ($dir, $filter);
    } else {
        # No slash — treat as filter in current dir
        ($!current-dir.Str, $expanded);
    }
}

method !on-text-changed(Str $text) {
    my ($dir-str, $filter) = self!parse-text($text);
    my $dir = $dir-str.IO;

    # If the directory portion changed AND exists, reload
    if $dir.d && $dir.resolve.Str ne $!current-dir.Str {
        $!current-dir = $dir.resolve;
        self!load-dir-entries;
    }

    self!apply-filter($filter);
}

method !on-enter() {
    my $selected = $!list.selected;
    self!activate-name($selected) if $selected.defined;
}

method !activate-name(Str $name) {
    return without $name;

    if $name eq '..' {
        return if $!current-dir.Str eq '/';
        $!current-dir = $!current-dir.parent;
        self!load-dir-entries;
        $!path-input.set-text($!current-dir.Str eq '/' ?? '/' !! $!current-dir.Str ~ '/');
        return;
    }

    my $target = $!current-dir.child($name);
    if $target.d {
        $!current-dir = $target.resolve;
        self!load-dir-entries;
        $!path-input.set-text($!current-dir.Str ~ '/');
    } elsif $target.e {
        $!select-supplier.emit($target.resolve.Str);
    }
}

method !on-tab() {
    my $text = $!path-input.text;
    my ($dir-str, $filter) = self!parse-text($text);

    # Get matching entries (excluding ..)
    my @matches = @!dir-entries.grep: -> $name {
        $name ne '..' && ($filter.chars == 0 || $name.lc.starts-with($filter.lc));
    };
    return unless @matches;

    if @matches.elems == 1 {
        # Single match — complete fully
        my $name = @matches[0];
        my $target = $!current-dir.child($name);
        if $target.d {
            $!current-dir = $target.resolve;
            self!load-dir-entries;
            $!path-input.set-text($target.Str ~ '/');
        } else {
            $!path-input.set-text($target.Str);
        }
    } else {
        # Multiple matches — complete to longest common prefix
        my $prefix = @matches[0];
        for @matches[1..*] -> $name {
            while $prefix.chars > 0 && !$name.lc.starts-with($prefix.lc) {
                $prefix = $prefix.substr(0, $prefix.chars - 1);
            }
        }
        if $prefix.chars > $filter.chars {
            # Use the actual casing from the prefix of the first match
            my $completed = @matches[0].substr(0, $prefix.chars);
            $!path-input.set-text($!current-dir.Str ~ '/' ~ $completed);
        }
    }
}

method !load-dir-entries() {
    @!dir-entries = ();
    @!dir-entries.push('..') unless $!current-dir.Str eq '/';

    my @contents = try { $!current-dir.dir.sort(*.basename).List } // ();
    for @contents -> $entry {
        my $name = $entry.basename;
        next if !$!show-dotfiles && $name.starts-with('.');
        if $entry.d {
            @!dir-entries.push($name);
        } elsif self!has-valid-extension($name) {
            @!dir-entries.push($name);
        }
    }

    $!list.set-items(@!dir-entries);
}

method !apply-filter(Str $filter) {
    if $filter.chars == 0 {
        $!list.set-items(@!dir-entries);
        return;
    }
    my $lc = $filter.lc;
    my @filtered = @!dir-entries.grep: -> $name {
        $name eq '..' || $name.lc.starts-with($lc);
    };
    $!list.set-items(@filtered);
}

method !has-valid-extension(Str $name --> Bool) {
    return True unless @!valid-extensions;
    my $ext = $name.IO.extension.lc;
    so $ext eq any(@!valid-extensions);
}
