=begin pod

=head1 NAME

Selkie::Widget::HelpOverlay - Modal listing keybinds for the focused widget chain

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::HelpOverlay;

# Bind globally on the screen root:
$root.on-key: 'ctrl+h', -> $ {
    my $help = Selkie::Widget::HelpOverlay.new(
        app             => $app,
        focused-widget  => $app.focused-widget,
    );
    $app.show-modal($help.build);
};

=end code

=head1 DESCRIPTION

Walks the focused widget and each ancestor up to (and including) the
screen root, collecting any C<on-key> binds that carry a
C<:description>. Renders a centred modal grouped by widget class so
users can see what shortcuts are reachable from their current focus.

Binds without descriptions are skipped — they're considered internal
plumbing (e.g. the editor cursor's character-handling) rather than
discoverable shortcuts. Authors opt in by passing C<:description> to
C<Widget.on-key>.

The overlay's modal sets C<dismiss-on-click-outside => True> by
default — clicking anywhere outside the help panel closes it. The
embedded Close button still works (Enter, Space, or click), and so
does Esc. The list itself doesn't yet scroll on overflow; widgets
with very long bind lists scroll their owner ScrollView via the
standard scroll-wheel routing.

=head1 SEE ALSO

=item L<Selkie::Widget> — C<on-key> registers binds, C<keybinds> reads them
=item L<Selkie::Widget::Modal> — the underlying overlay container

=end pod

unit class Selkie::Widget::HelpOverlay;

use Selkie::Widget;
use Selkie::Widget::Modal;
use Selkie::Widget::Text;
use Selkie::Widget::Button;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Sizing;
use Selkie::Style;

#| App reference. Untyped so snapshot-test stubs can stand in.
has $.app is required;

#| The widget that currently has focus. The overlay walks upward from
#| here through its C<.parent> chain to gather all reachable keybinds.
has Selkie::Widget $.focused-widget;

has Selkie::Widget::Modal $!modal;

method modal(--> Selkie::Widget::Modal) { $!modal }

method build(--> Selkie::Widget::Modal) {
    # dismiss-on-click-outside defaults True for HelpOverlay: it's a
    # lightweight informational overlay, and "click outside to dismiss"
    # is the standard convention for help / about / tooltip-style
    # popups. ConfirmModal stays at the safer False default.
    $!modal = Selkie::Widget::Modal.new(
        width-ratio              => 0.6,
        height-ratio             => 0.7,
        dismiss-on-click-outside => True,
    );

    my $body = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    $body.add: Selkie::Widget::Text.new(
        text   => ' Keyboard shortcuts',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    );
    $body.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));

    my @groups = self!collect-groups;
    if @groups.elems == 0 {
        $body.add: Selkie::Widget::Text.new(
            text   => '  (no documented keybinds in this context)',
            sizing => Sizing.fixed(1),
            style  => Selkie::Style.new(fg => 0x808090, italic => True),
        );
    } else {
        for @groups -> %g {
            $body.add: Selkie::Widget::Text.new(
                text   => " {%g<title>}",
                sizing => Sizing.fixed(1),
                style  => Selkie::Style.new(fg => 0xBB99FF, bold => True),
            );
            for %g<binds>.list -> %b {
                $body.add: Selkie::Widget::Text.new(
                    text   => sprintf('   %-14s  %s', %b<spec>, %b<description>),
                    sizing => Sizing.fixed(1),
                );
            }
            $body.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));
        }
    }

    $body.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    my $btn-row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
    $btn-row.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);
    my $close = Selkie::Widget::Button.new(label => 'Close (Esc)', sizing => Sizing.fixed(14));
    $btn-row.add($close);
    $body.add($btn-row);

    $close.on-press.tap: -> $ { $!app.close-modal };
    $!modal.on-close.tap: -> $ { $!app.close-modal };

    $!modal.set-content($body);
    $!app.focus($close) if $!app.can('focus');

    $!modal;
}

#|( Walk from $!focused-widget up through .parent collecting documented
    keybinds. Returns a list of { title, binds => [{ spec, description }, ...] }
    in focused-leaf-first order so the most-immediate context shows
    first. Widgets with no documented binds are omitted. )
method !collect-groups(--> List) {
    my @groups;
    my $w = $!focused-widget;
    my %seen;
    while $w {
        # Avoid cycles in pathological parent chains.
        last if %seen{$w.WHICH};
        %seen{$w.WHICH} = True;

        my @binds = $w.keybinds.grep({ .description.chars > 0 }).map({
            %( spec => .spec, description => .description )
        }).List;

        if @binds {
            @groups.push: %(
                title => $w.^name,
                binds => @binds,
            );
        }

        $w = $w.parent;
    }
    @groups.List;
}
