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

### has Bool $.dismiss-on-click-outside

When True, a primary mouse click outside the modal's content rectangle dismisses the modal — the framework calls `Selkie::App.close-modal`, restoring the pre-modal focus and revealing whatever was behind. Default False matches the keyboard focus-trap behavior: stray clicks in the dimmed backdrop are ignored. Subclasses override the default by passing `:dismiss-on-click-outside` to their parent constructor — `HelpOverlay` defaults to True (lightweight informational overlay), `ConfirmModal` stays False (a Yes/No decision shouldn't be silently abandoned).

### method content

```raku
method content() returns Selkie::Widget
```

The current content widget, or the `Selkie::Widget` type object when no content is set.

### method on-close

```raku
method on-close() returns Supply
```

Supply that emits `True` when `close` is called or the user dismisses the modal (Esc, or a click outside when `dismiss-on-click-outside` is set). Tap this to call `$app.close-modal` and run any post-close logic.

### method set-content

```raku
method set-content(
    Selkie::Widget $w,
    Bool :$destroy = Bool::True
) returns Mu
```

Install `$w` as the modal's content. Re-callable to swap content during a multi-step wizard. `:destroy` (default True) destroys the outgoing widget — the common case when content isn't reused. Pass `:!destroy` to keep the outgoing widget alive (its plane is parked far off-screen so its last-rendered cells don't bleed through behind the new content); call `set-content` with it again later to reinstall.

### method close

```raku
method close() returns Mu
```

Emit on `on-close`. Doesn't itself remove the modal from the App — the caller's tap is expected to call `$app.close-modal`.

### method focusable-descendants

```raku
method focusable-descendants() returns Seq
```

Focusable descendants of the modal's content subtree. `Selkie::App` uses this to scope Tab / Shift-Tab cycling to within the active modal — keyboard focus never escapes to the surrounding screen while the modal is up.

### method handle-resize

```raku
method handle-resize(
    Int $rows where { ... },
    Int $cols where { ... }
) returns Mu
```

Cascade a terminal resize to the content subtree. The content is sized to the same fraction of the parent that `render` uses (`width-ratio` by `height-ratio`) so its layout pass sees the right dimensions before the next render frame.

### method handle-event

```raku
method handle-event(
    Selkie::Event $ev
) returns Bool
```

Modal-level event handler. Only consults the modal's own keybinds (Esc-to-close by default). Per-content events are routed by `Selkie::App`'s dispatcher to the focused descendant inside the modal — modal-isolation is enforced at the App layer, not here.

### method destroy

```raku
method destroy() returns Mu
```

Destroy the modal: tear down the content subtree, the dim-background plane, and the modal's own plane. Always called by `Selkie::App` when the modal is removed from the stack — apps don't usually call this directly.

