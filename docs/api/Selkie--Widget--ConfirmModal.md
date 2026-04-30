NAME
====

Selkie::Widget::ConfirmModal - Pre-built yes/no confirmation dialog

SYNOPSIS
========

```raku
use Selkie::Widget::ConfirmModal;

my $cm = Selkie::Widget::ConfirmModal.new;
$cm.build(
    title     => 'Delete file?',
    message   => "Really delete 'report.pdf'?",
    yes-label => 'Delete',
    no-label  => 'Cancel',
);

$cm.on-result.tap: -> Bool $confirmed {
    $app.close-modal;
    do-delete() if $confirmed;
};

$app.show-modal($cm.modal);
$app.focus($cm.no-button);     # safe default
```

DESCRIPTION
===========

A wrapper around [Selkie::Widget::Modal](Selkie--Widget--Modal.md) with a pre-built title + message + yes/no button row. Emits a `Bool` on `on-result` when the user picks a button or presses Esc (Esc = False = No).

Use `$cm.no-button` (or `yes-button`) when calling `focus` on the app so the default focus is on the safer button.

Build the modal with `build(...)` and pass the returned Modal to `$app.show-modal`. The `.modal` accessor returns the same Modal after construction.

A primary mouse click on either button activates it — Selkie::App's coordinate dispatcher routes the click to the deepest hit (the Button widget itself), and Button's built-in click handler fires the same `on-press` path Enter / Space drive. The default `dismiss-on-click-outside` stays False (a Yes/No decision shouldn't be silently abandoned by a stray click).

EXAMPLES
========

Delete confirmation
-------------------

```raku
sub confirm-delete($item) {
    my $cm = Selkie::Widget::ConfirmModal.new;
    $cm.build(
        title     => 'Delete',
        message   => "Delete '{$item.name}'?",
        yes-label => 'Delete',
        no-label  => 'Cancel',
    );
    $cm.on-result.tap: -> Bool $confirmed {
        $app.close-modal;
        if $confirmed {
            $app.store.dispatch('item/delete', id => $item.id);
            $app.toast('Deleted');
        }
    };
    $app.show-modal($cm.modal);
    $app.focus($cm.no-button);
}
```

SEE ALSO
========

  * [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — underlying dialog

  * [Selkie::Widget::FileBrowser](Selkie--Widget--FileBrowser.md) — similar wrapper pattern for file picking

