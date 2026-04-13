NAME
====

Selkie::Widget::Modal - Centered overlay dialog with dimmed background

SYNOPSIS
========

```raku
use Selkie::Widget::Modal;
use Selkie::Layout::VBox;
use Selkie::Widget::Button;
use Selkie::Sizing;

my $modal = Selkie::Widget::Modal.new(
    width-ratio    => 0.5,
    height-ratio   => 0.3,
    dim-background => True,
);

my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$content.add: $some-text;
my $ok = Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.fixed(1));
$content.add($ok);
$modal.set-content($content);

$ok.on-press.tap:    -> $ { $app.close-modal };
$modal.on-close.tap: -> $ { $app.close-modal };

$app.show-modal($modal);
$app.focus($ok);
```

DESCRIPTION
===========

A dialog rendered centered on screen, sized as a fraction of the terminal. The background is dimmed by default so the dialog stands out. While the modal is active, [Selkie::App](Selkie--App.md) routes all events through it — Tab/Shift-Tab still cycle focus within the modal, Esc auto-closes.

For common confirm/cancel dialogs, use [Selkie::Widget::ConfirmModal](Selkie--Widget--ConfirmModal.md) which wraps Modal with a pre-built button row.

`set-content(:!destroy)` lets you swap content without destroying the outgoing widget — useful for multi-step wizards where each step is a separate content widget.

EXAMPLES
========

Input dialog
------------

```raku
my $modal = Selkie::Widget::Modal.new(width-ratio => 0.4, height-ratio => 0.2);
my $body = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$body.add: Selkie::Widget::Text.new(text => 'Rename', sizing => Sizing.fixed(1));
my $input = Selkie::Widget::TextInput.new(sizing => Sizing.fixed(1));
$body.add($input);
$modal.set-content($body);

$input.on-submit.tap: -> $new-name {
    $app.close-modal;
    $app.store.dispatch('rename', :$new-name);
};

$app.show-modal($modal);
$app.focus($input);
```

SEE ALSO
========

  * [Selkie::Widget::ConfirmModal](Selkie--Widget--ConfirmModal.md) — pre-built yes/no confirmation

  * [Selkie::Widget::FileBrowser](Selkie--Widget--FileBrowser.md) — pre-built file picker

  * [Selkie::App](Selkie--App.md) — `show-modal` and `close-modal` methods

