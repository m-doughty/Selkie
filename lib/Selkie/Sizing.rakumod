=begin pod

=head1 NAME

Selkie::Sizing - Declarative sizing model for widgets

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Sizing;

# Exactly 3 rows/cols
my $s1 = Sizing.fixed(3);

# 50% of the parent's available space
my $s2 = Sizing.percent(50);

# Flexible — takes a share of whatever's left after fixed+percent allocations
my $s3 = Sizing.flex;      # flex factor 1
my $s4 = Sizing.flex(2);   # flex factor 2 (twice as much as a flex(1) sibling)

=end code

=head1 DESCRIPTION

Every widget has a C<sizing> attribute that tells its parent layout how
much space it wants. Layouts (C<VBox>, C<HBox>) allocate space in three
passes:

=item B<Pass 1 — fixed>: each C<Sizing.fixed(n)> child gets exactly C<n> rows (VBox) or cols (HBox).
=item B<Pass 2 — percent>: each C<Sizing.percent(n)> child gets C<n%> of the parent's total size.
=item B<Pass 3 — flex>: whatever is left over is distributed proportionally to flex children by their flex factor.

Flex is the common case. Use fixed for header bars, toolbars, status lines.
Use percent sparingly — usually flex achieves the same thing more naturally.

=head1 EXAMPLES

=head2 A three-pane layout

Top bar is 1 row, bottom bar is 1 row, middle fills the rest.

=begin code :lang<raku>

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$root.add: Selkie::Widget::Text.new(text => 'header', sizing => Sizing.fixed(1));
$root.add: $main-content;                                  # sizing => Sizing.flex
$root.add: Selkie::Widget::Text.new(text => 'footer', sizing => Sizing.fixed(1));

=end code

=head2 A weighted split

Left pane gets one-third, right pane gets two-thirds.

=begin code :lang<raku>

my $columns = Selkie::Layout::HBox.new(sizing => Sizing.flex);
$columns.add: $sidebar;  # sizing => Sizing.flex(1)
$columns.add: $main;     # sizing => Sizing.flex(2)

=end code

=end pod

unit module Selkie::Sizing;

#| The three sizing strategies available to widgets.
#|
#| C<SizeFixed> — an exact row/col count. C<SizePercent> — a percentage of
#| the parent. C<SizeFlex> — a share of leftover space after fixed and
#| percent children have been allocated.
enum SizingMode is export (
    SizeFixed   => 'fixed',
    SizePercent => 'percent',
    SizeFlex    => 'flex',
);

#|( A sizing declaration on a widget. Build one with the factory methods
    C<Sizing.fixed>, C<Sizing.percent>, or C<Sizing.flex>. You rarely
    construct this directly with C<.new>. )
class Sizing is export {
    #| Which sizing strategy to use.
    has SizingMode $.mode is required;

    #| The numeric parameter for the strategy: row count for fixed,
    #| percentage for percent, flex factor for flex.
    has Numeric $.value is required;

    #| Fixed size in rows (VBox) or columns (HBox). Takes a non-negative integer.
    method fixed(UInt $n --> Sizing) { Sizing.new(mode => SizeFixed, value => $n) }

    #| Percent of the parent's available space. Pass any number 0–100.
    method percent(Numeric $n --> Sizing) { Sizing.new(mode => SizePercent, value => $n) }

    #|( Flexible share of leftover space. The factor defaults to 1; a
        flex(2) widget next to a flex(1) widget gets twice as much space.
        Use plain C<Sizing.flex> for most widgets and reserve non-default
        factors for cases where you genuinely want a 2:1 or 3:1 ratio. )
    method flex(Numeric $n = 1 --> Sizing) { Sizing.new(mode => SizeFlex, value => $n) }
}
