NAME
====

Selkie::Widget::FileBrowser - Shell-style file picker modal

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

A modal file picker built on top of `Modal`, `ListView`, and `TextInput`. Behaves like a shell prompt:

  * The path input shows the current directory + filename prefix

  * Typing filters the list below to matching entries

  * `Tab` autocompletes to the longest common prefix

  * `Enter` on a directory descends into it; on a file selects it

  * `Up`/`Down` navigate the list

  * `Esc` cancels without selecting

  * Single-click on a list row positions the cursor; double-click descends/selects (same path Enter takes)

Extension filtering is optional — pass `extensions =` ()> or omit to show everything. Hidden files (`.name`) are excluded unless `show-dotfiles` is True.

EXAMPLES
========

Import dialog
-------------

```raku
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
```

SEE ALSO
========

  * [Selkie::Widget::Modal](Selkie--Widget--Modal.md) — underlying dialog

