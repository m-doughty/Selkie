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
use Selkie::Widget::ConfirmModal;
use Selkie::Widget::CardList;
use Selkie::Store;
use Selkie::Widget::Toast;
use Selkie::Widget::FileBrowser;

=begin pod

=head1 NAME

Selkie - High-level TUI framework built on Notcurses

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie;

my $app = Selkie::App.new;

my $log = $app.root.add: Selkie::Widget::TextStream.new;
$log.append: "Hello, Selkie!";

$app.on-key('ctrl+q') { $app.quit }
$app.run;

=end code

=head1 DESCRIPTION

Selkie is a retained-mode TUI framework for Raku, built on top of Notcurses::Native.
It provides a hierarchical widget tree with automatic memory management, virtual scrolling,
theme support, and a reactive event system using Raku Supply/Channel primitives.

=head2 Key Features

=item Retained-mode widget tree with dirty tracking — only re-renders what changed
=item Virtual scrolling — renders only visible rows for maximum performance
=item Hierarchical layout with VBox, HBox, and Split containers
=item Streaming text panes with ring buffer and auto-follow
=item Image panes that integrate with the scroll system
=item Theme system with semantic style slots
=item Reactive input system with Supply-based events
=item Full memory management — users never touch low-level handles

=head1 AUTHOR

Matt Doughty <matt@apogee.guru>

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
