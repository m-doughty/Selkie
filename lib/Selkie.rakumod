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
