=begin pod

=head1 NAME

Selkie::Widget::Table - Scrollable tabular data with columns, header, and sorting

=head1 SYNOPSIS

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

A two-section widget: a header row (column labels, plus sort indicators
on sortable columns) and a scrollable body of data rows. Rows are
supplied as hashes keyed by column C<name>. Each cell is rendered as
the string form of the hash value unless the column has a custom
C<render> callback.

Column widths follow the same sizing model as L<Selkie::Layout::HBox>:
fixed, percent, or flex, allocated in three passes.

=head2 Navigation

Up / Down / PageUp / PageDown / Home / End move the row cursor; the
cursor is always fully visible (the body auto-scrolls). Enter fires
C<on-activate>. Mouse-wheel scrolls without changing the cursor.

=head2 Sorting

Set C<:sortable> on a column to enable sorting. Call C<sort-by($name)>
to cycle the given column through ascending → descending → unsorted.
The UI shows C<▲> / C<▼> next to the active sort column's label.

By default, sort comparison uses C<cmp> on the raw hash value. Pass
C<&sort-key> on the column for a custom comparator key (e.g. to sort
by length, by a derived property, etc).

=head1 EXAMPLES

=head2 Custom cell rendering

Render a size column as a human-readable string while still sorting on
the raw bytes:

=begin code :lang<raku>

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

=end code

=head2 Store-driven rows

Bind the table to a store path so filter/sort changes reflect
automatically:

=begin code :lang<raku>

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

=end code

=head2 Keybind-driven sorting

=begin code :lang<raku>

$table.on-key('s', -> $ {
    # Cycle sort column through the sortable ones
    my @sortable = $table.columns.grep(*<sortable>);
    my $current = $table.sort-column;
    my $idx = @sortable.first(*.<name> eq $current, :k) // -1;
    my $next = @sortable[($idx + 1) mod @sortable.elems];
    $table.sort-by($next<name>);
});

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::ListView> — single-column scrollable list
=item L<Selkie::Widget::CardList> — variable-height rich-content list
=item L<Selkie::Sizing> — the column-width sizing model

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;
use Selkie::Sizing;

unit class Selkie::Widget::Table does Selkie::Widget;

class Column {
    has Str $.name is required;
    has Str $.label is required;
    has Sizing $.sizing = Sizing.flex;
    has Bool $.sortable = False;
    has &.render;
    has &.sort-key;
}

has Column @!columns;
has @!rows;                         # Array[Hash]
has @!view-rows;                    # @rows possibly sorted; rendered directly
has UInt $!cursor = 0;
has UInt $!scroll-offset = 0;
has Bool $.show-scrollbar = True;

# Sort state
has Str $!sort-column;              # name of currently-sorted column, or Nil
has Str $!sort-direction = 'asc';   # 'asc' or 'desc'

has Supplier $!select-supplier = Supplier.new;
has Supplier $!activate-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Table) {
    %args<focusable> //= True;
    callwith(|%args);
}

# --- Accessors ------------------------------------------------------------

#| The list of registered columns in order. Read-only.
method columns(--> List) { @!columns.List }

#| The underlying row data. Read-only.
method rows(--> List) { @!rows.List }

#| Current cursor position within the (possibly sorted) view. C<0>-based.
method cursor(--> UInt) { $!cursor }

#| Name of the column currently sorted, or C<Nil> if the rows are in
#| insertion order.
method sort-column(--> Str) { $!sort-column }

#| C<'asc'> or C<'desc'>.
method sort-direction(--> Str) { $!sort-direction }

#| Supply emitting the cursor row index whenever the cursor moves.
method on-select(--> Supply) { $!select-supplier.Supply }

#| Supply emitting the cursor row index when the user hits Enter.
method on-activate(--> Supply) { $!activate-supplier.Supply }

#|( Fetch the row (hash) at a position in the current view. Honors the
    current sort. Returns C<Nil> if out of range. )
method row-at(UInt $idx) {
    return Nil unless $idx < @!view-rows.elems;
    @!view-rows[$idx];
}

#| The row currently under the cursor, or C<Nil> if the table is empty.
method selected-row() {
    self.row-at($!cursor);
}

# --- Column management ----------------------------------------------------

#|( Register a column. See the main pod for parameter meanings.

    C<name> keys into row hashes.
    C<label> is what appears in the header.
    C<sizing> controls column width (Sizing.fixed, .percent, .flex).
    C<sortable> enables sort-by for this column.
    C<render> optional C<($raw-value --> Str)> callback — without it the
    raw value is stringified.
    C<sort-key> optional C<($raw-value --> Cool)> callback — used to
    derive a sort key from the raw value. )
method add-column(
    Str:D :$name!,
    Str:D :$label!,
    Sizing :$sizing = Sizing.flex,
    Bool  :$sortable = False,
    :&render,
    :&sort-key,
) {
    @!columns.push: Column.new(
        :$name, :$label, :$sizing, :$sortable,
        :&render, :&sort-key,
    );
    self.mark-dirty;
}

#| Remove every column.
method clear-columns() {
    @!columns = ();
    self.mark-dirty;
}

# --- Row management -------------------------------------------------------

#|( Replace the row set. Preserves the current sort (re-applies it to
    the new rows). Cursor is clamped to bounds. Emits C<on-select> if
    the table is non-empty. )
method set-rows(@new-rows) {
    @!rows = @new-rows.Array;
    self!rebuild-view;

    # Clamp cursor
    if @!view-rows.elems == 0 {
        $!cursor = 0;
        $!scroll-offset = 0;
    } else {
        $!cursor = $!cursor min (@!view-rows.elems - 1);
        self!ensure-visible;
    }

    self.mark-dirty;
    $!select-supplier.emit($!cursor) if @!view-rows;
}

# --- Sorting --------------------------------------------------------------

#|( Sort the view by the given column name. Cycles through ascending →
    descending → unsorted on repeated calls for the same column. Set
    C<:direction> explicitly to skip the cycle. No-op if the column
    doesn't exist or isn't C<sortable>. )
method sort-by(Str:D $column-name, Str :$direction) {
    my $col = @!columns.first(*.name eq $column-name);
    return without $col;
    return unless $col.sortable;

    if $direction.defined {
        $!sort-column = $column-name;
        $!sort-direction = $direction;
    } elsif $!sort-column.defined && $!sort-column eq $column-name {
        given $!sort-direction {
            when 'asc'  { $!sort-direction = 'desc' }
            when 'desc' { $!sort-column = Str }   # cycle back to unsorted
        }
    } else {
        $!sort-column = $column-name;
        $!sort-direction = 'asc';
    }

    self!rebuild-view;
    self.mark-dirty;
}

#| Clear any active sort and restore insertion order.
method clear-sort() {
    $!sort-column = Str;
    self!rebuild-view;
    self.mark-dirty;
}

method !rebuild-view() {
    if $!sort-column.defined {
        my $col = @!columns.first(*.name eq $!sort-column);
        if $col {
            my &key = $col.sort-key // -> $v { $v };
            @!view-rows = @!rows.sort({ key($^a{$!sort-column}) cmp key($^b{$!sort-column}) }).Array;
            @!view-rows = @!view-rows.reverse.Array if $!sort-direction eq 'desc';
            return;
        }
    }
    @!view-rows = @!rows;
}

# --- Cursor + scroll ------------------------------------------------------

method select-index(UInt $idx) {
    return unless @!view-rows;
    my UInt $clamped = $idx min (@!view-rows.elems - 1);
    return if $clamped == $!cursor;
    $!cursor = $clamped;
    self!ensure-visible;
    self.mark-dirty;
    $!select-supplier.emit($!cursor);
}

method !ensure-visible() {
    my UInt $body-h = self!body-rows;
    return unless $body-h > 0;
    if $!cursor < $!scroll-offset {
        $!scroll-offset = $!cursor;
    } elsif $!cursor >= $!scroll-offset + $body-h {
        $!scroll-offset = $!cursor - $body-h + 1;
    }
}

method !body-rows(--> UInt) {
    # Reserve one row for the header
    (self.rows - 1) max 0;
}

method !max-offset(--> UInt) {
    my UInt $body-h = self!body-rows;
    @!view-rows.elems > $body-h ?? @!view-rows.elems - $body-h !! 0;
}

# --- Column layout --------------------------------------------------------

# Three-pass fixed / percent / flex allocation, matching HBox.
method !column-widths(--> Array) {
    my UInt $available = self.cols;
    $available -= 1 if $!show-scrollbar && @!view-rows.elems > self!body-rows;
    my UInt $total-width = $available;

    my @allocs = @!columns.map({ 0 });
    my Numeric $total-flex = 0;

    for @!columns.kv -> $i, $col {
        given $col.sizing.mode {
            when SizeFixed {
                @allocs[$i] = $col.sizing.value.UInt min $available;
                $available -= @allocs[$i];
            }
            when SizePercent {
                @allocs[$i] = ($total-width * $col.sizing.value / 100).floor.UInt min $available;
                $available -= @allocs[$i];
            }
            when SizeFlex {
                $total-flex += $col.sizing.value;
            }
        }
    }

    if $total-flex > 0 && $available > 0 {
        my UInt $remaining = $available;
        for @!columns.kv -> $i, $col {
            if $col.sizing.mode ~~ SizeFlex {
                my $share = ($available * $col.sizing.value / $total-flex).floor.UInt;
                $share = $share min $remaining;
                @allocs[$i] = $share;
                $remaining -= $share;
            }
        }
        if $remaining > 0 {
            for @!columns.kv.reverse -> $col, $i {
                if $col.sizing.mode ~~ SizeFlex {
                    @allocs[$i] += $remaining;
                    last;
                }
            }
        }
    }
    @allocs;
}

# --- Rendering ------------------------------------------------------------

method render() {
    return without self.plane;

    my UInt $max = self!max-offset;
    $!scroll-offset = $max if $!scroll-offset > $max;

    ncplane_erase(self.plane);

    return unless @!columns;

    my @widths = self!column-widths;

    # Header row
    self!render-header(@widths);

    # Body rows
    my UInt $body-h = self!body-rows;
    my UInt $visible = $body-h min @!view-rows.elems;
    my Bool $need-scrollbar = $!show-scrollbar && @!view-rows.elems > $body-h;

    for ^$visible -> $body-row {
        my UInt $row-idx = $!scroll-offset + $body-row;
        last if $row-idx >= @!view-rows.elems;

        my UInt $screen-row = 1 + $body-row;   # +1 for header
        my Bool $is-cursor = $row-idx == $!cursor;

        self!render-row($screen-row, @!view-rows[$row-idx], @widths, :$is-cursor);
    }

    self!render-scrollbar if $need-scrollbar;
    self.clear-dirty;
}

method !render-header(@widths) {
    my $header-style = self.theme.text-highlight;
    self.apply-style($header-style);

    my UInt $x = 0;
    for @!columns.kv -> $i, $col {
        my UInt $w = @widths[$i];
        next unless $w > 0;

        my $text = $col.label;
        # Sort indicator
        if $!sort-column.defined && $!sort-column eq $col.name {
            my $marker = $!sort-direction eq 'asc' ?? ' ▲' !! ' ▼';
            $text ~= $marker if $text.chars + $marker.chars <= $w;
        }
        $text = $text.substr(0, $w) if $text.chars > $w;
        $text = $text ~ (' ' x ($w - $text.chars)) if $text.chars < $w;

        ncplane_putstr_yx(self.plane, 0, $x, $text);
        $x += $w;
    }
}

method !render-row(UInt $screen-row, %row, @widths, Bool :$is-cursor) {
    my $base = self.theme.text;
    my $hl   = self.theme.text-highlight;
    my $bg   = self.theme.base;

    my UInt $x = 0;
    for @!columns.kv -> $i, $col {
        my UInt $w = @widths[$i];
        next unless $w > 0;

        if $is-cursor {
            ncplane_set_fg_rgb(self.plane, $hl.fg) if $hl.fg.defined;
            ncplane_set_bg_rgb(self.plane, $bg.bg // 0x2A2A3E);
            ncplane_set_styles(self.plane, $hl.styles);
        } else {
            ncplane_set_fg_rgb(self.plane, $base.fg) if $base.fg.defined;
            ncplane_set_bg_rgb(self.plane, $bg.bg // 0x1A1A2E);
            ncplane_set_styles(self.plane, 0);
        }

        my $raw = %row{$col.name};
        my $cell = do with $col.render {
            ($col.render)($raw).Str;
        } else {
            $raw.defined ?? $raw.Str !! '';
        };

        $cell = $cell.substr(0, $w) if $cell.chars > $w;
        $cell = $cell ~ (' ' x ($w - $cell.chars)) if $cell.chars < $w;

        ncplane_putstr_yx(self.plane, $screen-row, $x, $cell);
        $x += $w;
    }
}

method !render-scrollbar() {
    my UInt $body-h = self!body-rows;
    my UInt $sx = self.cols - 1;
    my $max = self!max-offset;
    return unless $max > 0;

    my $track-style = self.theme.scrollbar-track;
    my $thumb-style = self.theme.scrollbar-thumb;

    my Rat $thumb-ratio = $body-h / @!view-rows.elems;
    my UInt $thumb-h = ($body-h * $thumb-ratio).ceiling.UInt max 1;
    my UInt $thumb-y = (($!scroll-offset / $max) * ($body-h - $thumb-h)).floor.UInt;

    for ^$body-h -> $row {
        my UInt $screen-row = 1 + $row;   # skip header
        if $row >= $thumb-y && $row < $thumb-y + $thumb-h {
            ncplane_set_fg_rgb(self.plane, $thumb-style.fg) if $thumb-style.fg.defined;
            ncplane_set_bg_rgb(self.plane, $thumb-style.bg) if $thumb-style.bg.defined;
            ncplane_putstr_yx(self.plane, $screen-row, $sx, '┃');
        } else {
            ncplane_set_fg_rgb(self.plane, $track-style.fg) if $track-style.fg.defined;
            ncplane_set_bg_rgb(self.plane, $track-style.bg) if $track-style.bg.defined;
            ncplane_putstr_yx(self.plane, $screen-row, $sx, '│');
        }
    }
}

# --- Event handling -------------------------------------------------------

method handle-event(Selkie::Event $ev --> Bool) {
    if $ev.event-type ~~ KeyEvent {
        return True if self!check-keybinds($ev);
    }

    return False unless @!view-rows;

    given $ev.id {
        when NCKEY_UP    { self.select-index($!cursor - 1) if $!cursor > 0; return True }
        when NCKEY_DOWN  { self.select-index($!cursor + 1) if $!cursor + 1 < @!view-rows.elems; return True }
        when NCKEY_PGUP {
            my $jump = self!body-rows max 1;
            self.select-index($!cursor >= $jump ?? $!cursor - $jump !! 0);
            return True;
        }
        when NCKEY_PGDOWN {
            my $jump = self!body-rows max 1;
            self.select-index(($!cursor + $jump) min (@!view-rows.elems - 1));
            return True;
        }
        when NCKEY_HOME  { self.select-index(0); return True }
        when NCKEY_END   { self.select-index(@!view-rows.elems - 1); return True }
        when NCKEY_ENTER {
            $!activate-supplier.emit($!cursor);
            return True;
        }
    }

    if $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP {
                self.select-index($!cursor - 1) if $!cursor > 0;
                return True;
            }
            when NCKEY_SCROLL_DOWN {
                self.select-index($!cursor + 1) if $!cursor + 1 < @!view-rows.elems;
                return True;
            }
        }
    }

    False;
}
