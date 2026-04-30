=begin pod

=head1 NAME

Selkie - High-level TUI framework built on Notcurses

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie;

my $app = Selkie::App.new;
my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

my $log = Selkie::Widget::TextStream.new(sizing => Sizing.flex);
$root.add($log);
$log.append('Hello, Selkie!');

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.run;

=end code

=head1 DESCRIPTION

C<Selkie> is the umbrella module — C<use Selkie> imports everything in
one go, so you can refer to any class by its full name. Most apps work
fine with this; finer-grained imports are available if you prefer to be
explicit about what's in scope.

The framework itself is organised into several subnamespaces:

=item B<Core> — L<Selkie::App>, L<Selkie::Widget>, L<Selkie::Container>, L<Selkie::Store>, L<Selkie::ScreenManager>
=item B<Support types> — L<Selkie::Sizing>, L<Selkie::Style>, L<Selkie::Theme>, L<Selkie::Event>
=item B<Layouts> — L<Selkie::Layout::VBox>, L<Selkie::Layout::HBox>, L<Selkie::Layout::Split>
=item B<Display widgets> — L<Selkie::Widget::Text>, L<Selkie::Widget::RichText>, L<Selkie::Widget::TextStream>, L<Selkie::Widget::Image>, L<Selkie::Widget::ProgressBar>
=item B<Input widgets> — L<Selkie::Widget::TextInput>, L<Selkie::Widget::MultiLineInput>, L<Selkie::Widget::Button>, L<Selkie::Widget::Checkbox>, L<Selkie::Widget::RadioGroup>, L<Selkie::Widget::Select>
=item B<List widgets> — L<Selkie::Widget::ListView>, L<Selkie::Widget::CardList>, L<Selkie::Widget::ScrollView>
=item B<Chrome widgets> — L<Selkie::Widget::Border>, L<Selkie::Widget::Modal>, L<Selkie::Widget::ConfirmModal>, L<Selkie::Widget::FileBrowser>, L<Selkie::Widget::Toast>

Start with L<Selkie::App> for the big picture, L<Selkie::Widget> if you
want to write your own widgets, and L<Selkie::Store> for the reactive
state model. Every module has runnable examples in its Pod.

=head1 MOUSE SUPPORT

Selkie has first-class mouse support across every prebuilt widget.
You don't need to opt in — L<Selkie::App> enables button + drag events
on construction (via C<notcurses_mice_enable>), and the dispatcher
routes presses, drags, releases, and the scroll wheel through the
same C<handle-event> path as keystrokes.

=head2 Dispatch model

=item B<Keyboard> goes to the focused widget, then ancestors, then global keybinds (unchanged).
=item B<Mouse> goes to the deepest widget under the cursor, then ancestors, then global keybinds.
=item A primary press on a focusable widget gives it focus before the event is delivered, so mouse-driven activation matches keyboard-driven activation.
=item B<Drag capture>: a press on widget X routes subsequent drag and release events for that button to X, regardless of where the cursor is. This is what makes scrollbar drags and text-selection drags feel right when the cursor leaves the widget.
=item B<Modal isolation>: clicks outside the active modal are dropped by default. Modals can opt in to dismiss-on-click-outside by passing C<:dismiss-on-click-outside> to their constructor — L<Selkie::Widget::HelpOverlay> uses this.

=head2 Per-widget API

Same registration ergonomics as L<Selkie::Widget>'s C<on-key>:

=begin code :lang<raku>

# Click anywhere on the widget — primary button by default.
$widget.on-click: -> $ev {
    say "clicked at row {$widget.local-row($ev)}, col {$widget.local-col($ev)}";
};

# Right-click via :button(3); :button(0) catches any button.
$widget.on-click: -> $ev { open-context-menu }, button => 3;

# Scroll wheel.
$widget.on-scroll: -> $ev {
    given $ev.id {
        when NCKEY_SCROLL_UP   { ... }
        when NCKEY_SCROLL_DOWN { ... }
    }
};

# Drag (press + motion-with-button-held). Capture keeps these flowing
# even when the cursor leaves the widget's bounds.
$widget.on-drag: -> $ev {
    say "drag now at row {$ev.y - $widget.abs-y}";
};

# Low-level escape hatches — fire on every press / release.
$widget.on-mouse-down: -> $ev { ... };
$widget.on-mouse-up:   -> $ev { ... };

=end code

C<self.local-row($ev)> and C<self.local-col($ev)> translate the event's
absolute screen coordinates into widget-local cells (returning C<-1>
if the event is out of bounds). C<contains-point(y, x)> exposes the
same hit-test the framework uses internally.

=head2 Multi-click

Press events are annotated with their multiplicity in C<$ev.click-count>:
1 for a single click, 2 for a double-click, 3 for a triple-click. The
framework counts a press as a continuation of the previous click when
it lands on the same cell with the same button within 300 ms.
L<Selkie::Widget::TextInput> uses double / triple click to select word
/ all; L<Selkie::Widget::FileBrowser> uses double-click to descend into
directories; L<Selkie::Widget::ListView> uses double-click to fire
C<on-activate>.

=head2 Built-in widget behaviours

=item B<Button>, B<Checkbox> — primary click activates / toggles.
=item B<TabBar> — primary click activates the tab under the cursor.
=item B<RadioGroup>, B<ListView>, B<Table> — single-click selects the row; scroll wheel moves the cursor. Table also clicks the column header to cycle sort. ListView and Table fire C<on-activate> on double-click.
=item B<Select> — click toggles the dropdown; scroll wheel scrolls the open dropdown; click on a dropdown row commits.
=item B<TextInput>, B<MultiLineInput> — click positions the caret; drag selects; double-click selects the word; triple-click selects the line / buffer; Ctrl+A selects all; Ctrl+C / Ctrl+X emit on C<on-copy> / C<on-cut> (the framework doesn't own the system clipboard — wire OSC 52 / notcurses paste-buffer in your app).
=item B<CardList> — click selects the card under the cursor; scroll wheel moves between cards.
=item B<ScrollView>, B<TextStream> — scroll wheel scrolls; drag on the scrollbar column drags the thumb.
=item B<ConfirmModal>, B<CommandPalette>, B<FileBrowser> — clicks fall through to the embedded Button / ListView / TextInput, which handle them with their built-in behaviour.
=item B<HelpOverlay> — click outside dismisses; click the Close button to close.

Display-only widgets (Text, RichText, Image, Border, ProgressBar,
Spinner, Toast, Legend, all charts) don't react to mouse — Border
passes through to its content.

=head1 AUTHOR

Matt Doughty <matt@apogee.guru>

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.

=end pod

unit module Selkie;

use Selkie::App;
use Selkie::Widget;
use Selkie::Container;
use Selkie::Event;
use Selkie::Style;
use Selkie::Theme;
use Selkie::Sizing;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Layout::Split;
use Selkie::Widget::Text;
use Selkie::Widget::TextStream;
use Selkie::Widget::TextInput;
use Selkie::Widget::ScrollView;
use Selkie::Widget::Image;
use Selkie::Widget::ListView;
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Widget::MultiLineInput;
use Selkie::Widget::Modal;
use Selkie::ScreenManager;
use Selkie::Widget::Border;
use Selkie::Widget::Button;
use Selkie::Widget::Checkbox;
use Selkie::Widget::ConfirmModal;
use Selkie::Widget::CardList;
use Selkie::Widget::ProgressBar;
use Selkie::Widget::RadioGroup;
use Selkie::Widget::Select;
use Selkie::Widget::Spinner;
use Selkie::Widget::TabBar;
use Selkie::Widget::CommandPalette;
use Selkie::Widget::Table;
use Selkie::Store;
use Selkie::Widget::Toast;
use Selkie::Widget::FileBrowser;
