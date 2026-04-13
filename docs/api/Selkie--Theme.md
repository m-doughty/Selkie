NAME
====

Selkie::Theme - Named palette of `Selkie::Style` slots

SYNOPSIS
========

```raku
use Selkie::Style;
use Selkie::Theme;

# Build a custom theme
my $theme = Selkie::Theme.new(
    base              => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x000000),
    text              => Selkie::Style.new(fg => 0xEEEEEE),
    text-dim          => Selkie::Style.new(fg => 0x888888),
    text-highlight    => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
    border            => Selkie::Style.new(fg => 0x444444),
    border-focused    => Selkie::Style.new(fg => 0x00FF00, bold => True),
    input             => Selkie::Style.new(fg => 0xEEEEEE, bg => 0x111111),
    input-focused     => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x222222),
    input-placeholder => Selkie::Style.new(fg => 0x666666, italic => True),
    scrollbar-track   => Selkie::Style.new(fg => 0x333333),
    scrollbar-thumb   => Selkie::Style.new(fg => 0x00FF00),
    divider           => Selkie::Style.new(fg => 0x444444),
);

# Use it app-wide
my $app = Selkie::App.new(:$theme);
```

DESCRIPTION
===========

A theme is a collection of named `Selkie::Style` slots — one per visual role in the framework. Widgets look up slots by name (`self.theme.border`, `self.theme.text-highlight`, etc.) so you can restyle the whole app by providing a different theme.

Themes are inherited through the widget tree: a widget's effective theme is its own explicit theme (if set), otherwise its parent's, falling back to `Selkie::Theme.default`.

EXAMPLES
========

Default theme
-------------

If you don't pass one to `Selkie::App`, the built-in dark palette is used:

```raku
my $app = Selkie::App.new;   # uses Selkie::Theme.default
```

Scoping a different theme to a subtree
--------------------------------------

Give a specific panel a different palette without affecting the rest of the app:

```raku
my $warning-theme = Selkie::Theme.default;
# (imagine we mutated this or built a fresh one with red borders)
$warning-panel.set-theme($warning-theme);
```

Runtime theme swap
------------------

Subscribe a root container to a store path that holds the current theme, and swap at will:

```raku
$store.register-handler('theme/toggle', -> $st, % {
    my $dark = $st.get-in('dark') // True;
    (db => { dark => !$dark },);
});

$store.subscribe-with-callback(
    'theme',
    -> $s { $s.get-in('dark') // True },
    -> Bool $dark { $root.set-theme($dark ?? dark-theme() !! light-theme()) },
    $root,
);
```

SLOTS
=====

Every slot is a `Selkie::Style`. All slots are `is required` — a theme must explicitly define every one.

  * `base` — default background plus text color

  * `text`, `text-dim`, `text-highlight` — normal, subdued, and emphasised text

  * `border`, `border-focused` — borders when unfocused vs containing the focused widget

  * `input`, `input-focused`, `input-placeholder` — text input states

  * `scrollbar-track`, `scrollbar-thumb` — vertical scrollbar

  * `divider` — the split bar in `Selkie::Layout::Split`

Custom slots
------------

Extend a theme with project-specific slots via the `%.custom` hash. Widgets can look them up via `self.theme.slot('my-slot-name')`:

```raku
my $theme = Selkie::Theme.new(
    ...,
    custom => {
        'chat-bot'  => Selkie::Style.new(fg => 0x9ECE6A),
        'chat-user' => Selkie::Style.new(fg => 0x7AA2F7),
    },
);

# In a custom widget:
self.apply-style(self.theme.slot('chat-bot'));
```

`slot` falls back to the `base` style if the name isn't registered.

### has Selkie::Style $.base

The base background and default text color for the theme.

### has Selkie::Style $.border

Border style for unfocused borders.

### has Selkie::Style $.border-focused

Border style for borders whose descendant has focus. Auto-applied by `Selkie::Widget::Border` based on store focus state.

### has Selkie::Style $.text

Default text style.

### has Selkie::Style $.text-dim

Subdued text — for captions, help text, placeholder-ish content.

### has Selkie::Style $.text-highlight

Emphasised text — selected list items, highlighted values.

### has Selkie::Style $.input

Text input style when unfocused.

### has Selkie::Style $.input-focused

Text input style when focused.

### has Selkie::Style $.input-placeholder

Placeholder text style (shown when an input is empty and unfocused).

### has Selkie::Style $.scrollbar-track

Scrollbar track (the background rail).

### has Selkie::Style $.scrollbar-thumb

Scrollbar thumb (the filled bar showing position).

### has Selkie::Style $.divider

Divider line in `Selkie::Layout::Split`.

### has Associative[Selkie::Style] %.custom

Extra application-specific slots. Keyed by name, values are `Selkie::Style`. Look them up via `slot(name)`.

### method slot

```raku
method slot(
    Str:D $name
) returns Selkie::Style
```

Fetch a named custom slot, falling back to `base` if the name isn't registered. Useful for app-specific categories of styling that don't fit the built-in slots.

### method default

```raku
method default() returns Selkie::Theme
```

The built-in dark theme. Used automatically by `Selkie::App` when no theme is provided. Browse the implementation for exact colors — it's a cool blue-grey palette with accent on 0x7AA2F7.

