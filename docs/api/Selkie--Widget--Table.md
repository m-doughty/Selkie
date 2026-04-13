NAME
====

Selkie::Widget::Table - Scrollable tabular data with columns, header, and sorting

SYNOPSIS
========

```raku
use Selkie::Widget::Table;
use Selkie::Sizing;

my $table = Selkie::Widget::Table.new(sizing => Sizing.flex);

$table.add-column(name => 'id',    label => 'ID',    sizing => Sizing.fixed(6));
$table.add-column(name => 'name',  label => 'Name',  sizing => Sizing.flex,     :sortable);
$table.add-column(name => 'size',  label => 'Size',  sizing => Sizing.fixed(10), :sortable);

$table.set-rows([
    { id => 1, name => 'alpha', size => 42_000 },
    { id => 2, name => 'beta',  size => 1_200_000 },
    { id => 3, name => 'gamma', size => 873 },
]);

$table.on-select.tap:   -> UInt $idx { show-detail($idx) };
$table.on-activate.tap: -> UInt $idx { open-row($idx) };
```

DESCRIPTION
===========

A two-section widget: a header row (column labels, plus sort indicators on sortable columns) and a scrollable body of data rows. Rows are supplied as hashes keyed by column `name`. Each cell is rendered as the string form of the hash value unless the column has a custom `render` callback.

Column widths follow the same sizing model as [Selkie::Layout::HBox](Selkie--Layout--HBox.md): fixed, percent, or flex, allocated in three passes.

Navigation
----------

Up / Down / PageUp / PageDown / Home / End move the row cursor; the cursor is always fully visible (the body auto-scrolls). Enter fires `on-activate`. Mouse-wheel scrolls without changing the cursor.

Sorting
-------

Set `:sortable` on a column to enable sorting. Call `sort-by($name)` to cycle the given column through ascending → descending → unsorted. The UI shows `▲` / `▼` next to the active sort column's label.

By default, sort comparison uses `cmp` on the raw hash value. Pass `&sort-key` on the column for a custom comparator key (e.g. to sort by length, by a derived property, etc).

EXAMPLES
========

Custom cell rendering
---------------------

Render a size column as a human-readable string while still sorting on the raw bytes:

```raku
sub human(Int $bytes) {
    given $bytes {
        when * < 1024          { "{$bytes} B" }
        when * < 1024 ** 2     { sprintf '%.1f KB', $bytes / 1024 }
        when * < 1024 ** 3     { sprintf '%.1f MB', $bytes / (1024 ** 2) }
        default                { sprintf '%.1f GB', $bytes / (1024 ** 3) }
    }
}

$table.add-column(
    name     => 'size',
    label    => 'Size',
    sizing   => Sizing.fixed(10),
    sortable => True,
    render   => -> $raw { human($raw) },    # display
    sort-key => -> $raw { $raw.Int },       # sort by number, not string
);
```

Store-driven rows
-----------------

Bind the table to a store path so filter/sort changes reflect automatically:

```raku
$app.store.subscribe-with-callback(
    'files-table',
    -> $s { ($s.get-in('files') // []).List },
    -> @rows { $table.set-rows(@rows) },
    $table,
);

$table.on-activate.tap: -> UInt $idx {
    my $row = $table.row-at($idx);
    $app.store.dispatch('file/open', id => $row<id>);
};
```

Keybind-driven sorting
----------------------

```raku
$table.on-key('s', -> $ {
    # Cycle sort column through the sortable ones
    my @sortable = $table.columns.grep(*<sortable>);
    my $current = $table.sort-column;
    my $idx = @sortable.first(*.<name> eq $current, :k) // -1;
    my $next = @sortable[($idx + 1) mod @sortable.elems];
    $table.sort-by($next<name>);
});
```

SEE ALSO
========

  * [Selkie::Widget::ListView](Selkie--Widget--ListView.md) — single-column scrollable list

  * [Selkie::Widget::CardList](Selkie--Widget--CardList.md) — variable-height rich-content list

  * [Selkie::Sizing](Selkie--Sizing.md) — the column-width sizing model

### method columns

```raku
method columns() returns List
```

The list of registered columns in order. Read-only.

### method rows

```raku
method rows() returns List
```

The underlying row data. Read-only.

### method cursor

```raku
method cursor() returns UInt
```

Current cursor position within the (possibly sorted) view. `0`-based.

### method sort-column

```raku
method sort-column() returns Str
```

Name of the column currently sorted, or `Nil` if the rows are in insertion order.

### method sort-direction

```raku
method sort-direction() returns Str
```

`'asc'` or `'desc'`.

### method on-select

```raku
method on-select() returns Supply
```

Supply emitting the cursor row index whenever the cursor moves.

### method on-activate

```raku
method on-activate() returns Supply
```

Supply emitting the cursor row index when the user hits Enter.

### method row-at

```raku
method row-at(
    Int $idx where { ... }
) returns Mu
```

Fetch the row (hash) at a position in the current view. Honors the current sort. Returns `Nil` if out of range.

### method selected-row

```raku
method selected-row() returns Mu
```

The row currently under the cursor, or `Nil` if the table is empty.

### method add-column

```raku
method add-column(
    Str:D :$name!,
    Str:D :$label!,
    Selkie::Sizing::Sizing :$sizing = Code.new,
    Bool :$sortable = Bool::False,
    :&render,
    :&sort-key
) returns Mu
```

Register a column. See the main pod for parameter meanings. `name` keys into row hashes. `label` is what appears in the header. `sizing` controls column width (Sizing.fixed, .percent, .flex). `sortable` enables sort-by for this column. `render` optional `($raw-value --` Str)> callback — without it the raw value is stringified. `sort-key` optional `($raw-value --` Cool)> callback — used to derive a sort key from the raw value.

### method clear-columns

```raku
method clear-columns() returns Mu
```

Remove every column.

### method set-rows

```raku
method set-rows(
    @new-rows
) returns Mu
```

Replace the row set. Preserves the current sort (re-applies it to the new rows). Cursor is clamped to bounds. Emits `on-select` if the table is non-empty.

### method sort-by

```raku
method sort-by(
    Str:D $column-name,
    Str :$direction
) returns Mu
```

Sort the view by the given column name. Cycles through ascending → descending → unsorted on repeated calls for the same column. Set `:direction` explicitly to skip the cycle. No-op if the column doesn't exist or isn't `sortable`.

### method clear-sort

```raku
method clear-sort() returns Mu
```

Clear any active sort and restore insertion order.

