NAME
====

Selkie::Widget::TabBar - Horizontal tab strip integrated with ScreenManager

SYNOPSIS
========

```raku
use Selkie::Widget::TabBar;
use Selkie::Sizing;

my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'tasks',  label => 'Tasks');
$tabs.add-tab(name => 'notes',  label => 'Notes');
$tabs.add-tab(name => 'stats',  label => 'Stats');

# Tap to react to user selection:
$tabs.on-tab-selected.tap: -> Str $name {
    $app.switch-screen($name);
};
```

DESCRIPTION
===========

A one-line horizontal strip of named tabs. The active tab is highlighted with the theme's `text-highlight` slot; others render in the default `text` slot. Focusable — Left/Right arrows move the active tab, `Enter` fires `on-tab-selected` (which you typically tap to call `$app.switch-screen`).

Tabs are identified by an opaque `name` string and displayed as a `label`. The name is what's emitted on `on-tab-selected` — choose something that matches your registered screen names for a zero-effort integration with `Selkie::ScreenManager`.

`TabBar` also has convenient integration with `ScreenManager`: call `sync-to-app($app)` to make the active tab reflect `$app.screen-manager.active-screen` automatically via a store subscription.

EXAMPLES
========

Wiring to ScreenManager
-----------------------

The canonical pattern: one tab per screen, selection dispatches a screen switch, and the bar keeps itself in sync if the screen changes from elsewhere:

```raku
my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'inbox',  label => 'Inbox');
$tabs.add-tab(name => 'sent',   label => 'Sent');
$tabs.add-tab(name => 'drafts', label => 'Drafts');

$tabs.on-tab-selected.tap: -> Str $name {
    $app.switch-screen($name);
};

# Keep the bar's active tab in sync with whatever's actually showing
$tabs.sync-to-app($app);
```

Without ScreenManager
---------------------

Tabs don't have to drive screen switches — you can use them as a lightweight "mode" selector for a single screen's content:

```raku
my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'recent', label => 'Recent');
$tabs.add-tab(name => 'saved',  label => 'Saved');
$tabs.add-tab(name => 'all',    label => 'All');

$tabs.on-tab-selected.tap: -> Str $name {
    $app.store.dispatch('view/mode-changed', mode => $name);
};
```

SEE ALSO
========

  * [Selkie::ScreenManager](Selkie--ScreenManager.md) — the multi-screen registry TabBar typically drives

  * [Selkie::App](Selkie--App.md) — screen-scoped keybinds complement per-tab views

### method add-tab

```raku
method add-tab(
    Str:D :$name!,
    Str:D :$label!
) returns Mu
```

Register a tab. `name` is the identifier (usually matches a screen name); `label` is what's shown to the user. Tabs render in the order they're added.

### method remove-tab

```raku
method remove-tab(
    Str:D $name
) returns Mu
```

Remove a tab by name. If the removed tab was active, activation falls to the tab that was to its left (or index 0).

### method clear-tabs

```raku
method clear-tabs() returns Mu
```

Remove all tabs.

### method active-name

```raku
method active-name() returns Str
```

Tab name of the currently active tab, or `Nil` if the bar is empty.

### method active-index

```raku
method active-index() returns UInt
```

Index of the active tab.

### method tab-names

```raku
method tab-names() returns List
```

Tab names in order.

### method select-by-name

```raku
method select-by-name(
    Str:D $name
) returns Mu
```

Activate the tab with this name. No-op if the name isn't registered or already active. Emits `on-tab-selected`.

### method select-index

```raku
method select-index(
    Int $idx where { ... }
) returns Mu
```

Activate the tab at this index. No-op if already active or out of range.

### method set-active-name-silent

```raku
method set-active-name-silent(
    Str:D $name
) returns Mu
```

Silently set the active index (no `on-tab-selected` emit). Use from a store subscription that syncs the bar to external state — prevents feedback loops.

### method on-tab-selected

```raku
method on-tab-selected() returns Supply
```

Supply emitting the `name` of the newly-active tab whenever the user changes it (or a programmatic `select-by-name` fires).

### method sync-to-app

```raku
method sync-to-app(
    $app
) returns Mu
```

Install a store subscription that keeps this TabBar's active tab synced to `$app.screen-manager.active-screen`. Makes the bar self-consistent: if you call `$app.switch-screen(...)` elsewhere, the bar's highlight follows along.

