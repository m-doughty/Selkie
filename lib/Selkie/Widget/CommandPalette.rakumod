=begin pod

=head1 NAME

Selkie::Widget::CommandPalette - VS-Code-style fuzzy-filtered action launcher

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::CommandPalette;

my $palette = Selkie::Widget::CommandPalette.new;
$palette.add-command(label => 'New note',       -> { create-note });
$palette.add-command(label => 'Quit',           -> { $app.quit });
$palette.add-command(label => 'Toggle theme',   -> { toggle-theme });

my $modal = $palette.build;

# Close the modal and run the command when the user activates one.
$palette.on-command.tap: -> $cmd {
    $app.close-modal;
    $cmd.action.();
};

# Bind Ctrl+P to open the palette
$app.on-key('ctrl+p', -> $ {
    $palette.reset;
    $app.show-modal($modal);
    $app.focus($palette.focusable-widget);
});

=end code

=head1 DESCRIPTION

A modal that slides in a search box over a scrollable action list.
Type to filter, arrows to navigate, Enter to run, Esc to cancel.
Commands are registered once — each carries a label and an action
callback.

Filtering is a simple case-insensitive substring match. Matches are
ranked with earlier-position-in-label winning over later-position
matches; ties fall back to insertion order. Good enough for action
palettes with hundreds of commands, which covers most real use.

The modal closes itself on Enter before invoking the callback — so
the callback runs with focus restored to whatever had it before the
palette opened. If you need the palette to stay open (e.g. for chained
commands), call C<$app.show-modal> again from inside the callback.

=head1 EXAMPLES

=head2 App-wide command palette

=begin code :lang<raku>

my $palette = Selkie::Widget::CommandPalette.new;

# Register at startup, wherever your commands live:
$palette.add-command(label => 'Save document',
    -> { $app.store.dispatch('doc/save') });
$palette.add-command(label => 'New document',
    -> { $app.store.dispatch('doc/new') });
$palette.add-command(label => 'Close document',
    -> { $app.store.dispatch('doc/close') });
$palette.add-command(label => 'Toggle dark mode',
    -> { $app.store.dispatch('theme/toggle') });

my $modal = $palette.build;

$app.on-key('ctrl+p', -> $ {
    $palette.reset;                # clear filter + reset selection
    $app.show-modal($modal);
    $app.focus($palette.focusable-widget);
});

=end code

=head2 Contextual palette for a specific screen

Build separate palettes for different contexts — e.g. an editor palette
distinct from an inbox palette. Register each on a screen-scoped keybind:

=begin code :lang<raku>

$app.on-key('ctrl+p', :screen('editor'), -> $ {
    $app.show-modal($editor-palette.build);
    $app.focus($editor-palette.focusable-widget);
});

$app.on-key('ctrl+p', :screen('inbox'), -> $ {
    $app.show-modal($inbox-palette.build);
    $app.focus($inbox-palette.focusable-widget);
});

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Modal> — underlying modal
=item L<Selkie::Widget::FileBrowser> — similar wrapper pattern for file picking

=end pod

use Selkie::Widget::Modal;
use Selkie::Widget::TextInput;
use Selkie::Widget::ListView;
use Selkie::Widget::Text;
use Selkie::Layout::VBox;
use Selkie::Sizing;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::CommandPalette;

class Command {
    has Str $.label is required;
    has &.action is required;
}

has Command @!commands;
has Command @!filtered;          # currently-visible subset in filter order
has Selkie::Widget::Modal $!modal;
has Selkie::Widget::TextInput $!input;
has Selkie::Widget::ListView $!list;
has Str $!last-query = '';
has Supplier $!command-supplier = Supplier.new;

#| Supply emitting the activated C<Command> when the user hits Enter on
#| a filtered row. Tap this to close the modal and run the action.
method on-command(--> Supply) { $!command-supplier.Supply }

#|( Register a command. C<label> is shown in the list and matched against
    the user's filter query; the positional C<&action> is called with no
    arguments when the user activates the row.

    Typical usage puts the action block at the call-site tail:

        $palette.add-command(label => 'Save', -> { save-document });
)
method add-command(&action, Str:D :$label!) {
    @!commands.push(Command.new(:$label, :&action));
    self!refilter if $!list;
}

#|( Remove every registered command. Useful if commands are context-dependent
    and the palette is rebuilt on open. )
method clear-commands() {
    @!commands = ();
    self!refilter if $!list;
}

#| Reset the filter and cursor to fresh state. Call before re-opening
#| the palette so the user starts with the full list.
method reset() {
    $!input.set-text-silent('') if $!input;
    $!last-query = '';
    self!refilter if $!list;
}

#|( Build the modal and wire its widgets. Call once at setup; cache the
    returned Modal and pass it to C<$app.show-modal> whenever the palette
    should open. Safe to call multiple times — subsequent calls return
    the same modal. )
method build(
    Rat :$width-ratio  = 0.5,
    Rat :$height-ratio = 0.5,
    --> Selkie::Widget::Modal
) {
    return $!modal if $!modal;

    $!modal = Selkie::Widget::Modal.new(:$width-ratio, :$height-ratio);

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    $content.add: Selkie::Widget::Text.new(
        text   => ' Commands',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    );

    $!input = Selkie::Widget::TextInput.new(
        sizing      => Sizing.fixed(1),
        placeholder => 'Type to filter...',
    );
    $content.add($!input);

    $!list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
    $content.add($!list);

    $content.add: Selkie::Widget::Text.new(
        text   => ' ↑↓: navigate   Enter: run   Esc: cancel',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x666666, italic => True),
    );

    $!modal.set-content($content);

    # Filter on every keystroke
    $!input.on-change.tap: -> $q {
        $!last-query = $q;
        self!refilter;
    };

    # Enter in the input activates the currently-highlighted command.
    # We consume the submit so the modal doesn't close via plain Enter.
    $!input.on-submit.tap: -> $ {
        self!activate-cursor;
    };

    # Down arrow in the input moves the list cursor — standard palette UX.
    $!input.on-key('down', -> $ {
        my @items = $!list.items;
        if @items.elems > 0 && $!list.cursor < @items.elems - 1 {
            $!list.select-index($!list.cursor + 1);
        }
    });
    $!input.on-key('up', -> $ {
        if $!list.cursor > 0 {
            $!list.select-index($!list.cursor - 1);
        }
    });

    # Activating via the list directly (if the user somehow moves focus there)
    $!list.on-activate.tap: -> $ { self!activate-cursor };

    self!refilter;
    $!modal;
}

#| Which widget should receive initial focus when the modal opens.
#| The TextInput — typing immediately filters without pressing Tab.
method focusable-widget() { $!input }

method modal() { $!modal }

method !refilter() {
    return without $!list;
    my $q = $!last-query.lc.trim;
    if $q.chars == 0 {
        @!filtered = @!commands;
    } else {
        # Simple substring match, ranked by earliest match position.
        my @scored = @!commands.map(-> $cmd {
            my $pos = $cmd.label.lc.index($q);
            $pos.defined ?? { :cmd($cmd), :pos($pos) } !! Nil;
        }).grep(*.defined);

        @!filtered = @scored.sort(*<pos>).map(*<cmd>).Array;
    }

    $!list.set-items(@!filtered.map(*.label).List);
}

method !activate-cursor() {
    return without $!list;
    return unless @!filtered;
    my $idx = $!list.cursor;
    return unless $idx < @!filtered.elems;
    $!command-supplier.emit(@!filtered[$idx]);
}
