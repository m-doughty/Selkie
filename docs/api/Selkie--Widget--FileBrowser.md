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

### method on-select

```raku
method on-select() returns Supply
```

Supply that emits the selected absolute path (Str) when the user activates a file. Esc cancels and never emits — handle close-on-Esc via the Modal's standard dismissal.

### method build

```raku
method build(
    Str :$start-dir = Code.new,
    :@extensions,
    Bool :$show-dotfiles = Bool::False,
    Rat :$width-ratio = 0.6,
    Rat :$height-ratio = 0.7
) returns Selkie::Widget::Modal
```

Build the file picker modal. Returns the underlying Modal so the caller can pass it directly to `$app.show-modal`. `:extensions` filters by suffix (case-insensitive); empty array shows all files. `:show-dotfiles` includes hidden files. Re-callable to rebuild at a different start directory.

### method focusable-widget

```raku
method focusable-widget() returns Selkie::Widget::TextInput
```

The widget to pass to `$app.focus` after `show-modal`. Returns the path TextInput — typing filters the list, Tab autocompletes, Up/Down navigate, Enter selects.

### method list

```raku
method list() returns Selkie::Widget::ListView
```

The internal ListView, exposed for callers that want to override selection logic or read the visible items.

### method path-input

```raku
method path-input() returns Selkie::Widget::TextInput
```

The internal path TextInput, exposed for callers that want to pre-fill it or attach extra `on-key` handlers.

