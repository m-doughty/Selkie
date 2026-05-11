NAME
====

Selkie::Widget::ViewportedCardList - Row-scrolled selectable list of card widgets

DESCRIPTION
===========

Like [Selkie::Widget::CardList](Selkie--Widget--CardList.md), each item is an arbitrary widget with a logical height and optional focus border. Unlike CardList, scrolling is by content row: a viewport can start in the middle of any card.

### method copy-cells

```raku
method copy-cells(
    Notcurses::Native::Types::NcplaneHandle $src,
    Int :$src-y!,
    Int :$src-x!,
    Int :$dst-y!,
    Int :$dst-x!,
    Int :$rows! where { ... },
    Int :$cols! where { ... }
) returns Mu
```

Per-cell read+write loop using heap-stable primitives. Notcurses's `ncplane_at_yx` returns a malloc'd `char*` the caller is contractually obligated to free (see F<notcurses/doc/man/man3/notcurses_plane.3.md:512-514>); the Raku binding marshals it as `Str` without freeing the underlying C buffer, so a hot per-cell loop over every cell of every visible widget per frame leaks a few bytes thousands of times a second. That's the exact pattern called out in F<memory/nativecall_str_free_trap.md>, so prefer the cell-based read here: `ncplane_at_yx_cell` fills a caller-owned `Nccell` (no malloc) and `nccell_extended_gcluster` returns a pointer INTO the plane's existing egcpool (caller does NOT free). To preserve `ncplane_at_yx`'s behaviour of substituting the plane's base cell when a position has an empty glyph (see F<src/lib/notcurses.c:250-264>), pre-fetch the base cell once per source plane and substitute its EGC / stylemask / channels when the read cell has an empty gcluster. Without this fallback, "interior" cells of a Border (the space inside the box) would not be copied to the destination plane and would show through to whatever was painted there before.

