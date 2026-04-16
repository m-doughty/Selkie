#!/usr/bin/env raku
#
# Subprocess helper for xt/03-chart-integration.rakutest.
# Renders a panel containing every chart widget at the terminal size
# passed as command-line args (rows, cols). Exits 0 on success, 1 on
# any exception.
#
# Usage: raku -I lib xt/chart-panel-render.raku <rows> <cols>

use lib 'lib';

use Selkie::Test::Snapshot;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Sizing;

use Selkie::Widget::Sparkline;
use Selkie::Widget::Plot;
use Selkie::Widget::BarChart;
use Selkie::Widget::Histogram;
use Selkie::Widget::Heatmap;
use Selkie::Widget::ScatterPlot;
use Selkie::Widget::LineChart;

sub MAIN(UInt $rows, UInt $cols) {
    my $panel = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    my $top = Selkie::Layout::HBox.new(sizing => Sizing.fixed(8));
    $top.add: Selkie::Widget::Sparkline.new(
        data   => (1..40).map(*.Real).list,
        sizing => Sizing.flex,
    );
    $top.add: Selkie::Widget::Plot.new(
        type   => 'uint',
        min-y  => 0,
        max-y  => 100,
        sizing => Sizing.flex,
    );

    my $mid = Selkie::Layout::HBox.new(sizing => Sizing.fixed(10));
    $mid.add: Selkie::Widget::BarChart.new(
        data => [
            { label => 'a', value =>  5 },
            { label => 'b', value => 12 },
            { label => 'c', value =>  8 },
        ],
        sizing => Sizing.flex,
    );
    $mid.add: Selkie::Widget::Histogram.new(
        values => (1..50).map(*.Real).list,
        bins   => 5,
        sizing => Sizing.flex,
    );
    $mid.add: Selkie::Widget::Heatmap.new(
        data   => ((^4).map: -> $r { (^4).map: -> $c { ($r + $c) / 6.0 } }),
        sizing => Sizing.flex,
    );

    my $bot = Selkie::Layout::HBox.new(sizing => Sizing.flex);
    $bot.add: Selkie::Widget::ScatterPlot.new(
        series => [{
            label => 'cluster',
            points => (1..20).map: { ($_ * 5) => ($_ * 5) },
        }],
        x-min  => 0, x-max => 100,
        y-min  => 0, y-max => 100,
        sizing => Sizing.flex,
    );
    $bot.add: Selkie::Widget::LineChart.new(
        series => [{ label => 'wave',
                      values => (^30).map: { (sin($_ * 0.3) * 50 + 50).Int } }],
        y-min  => 0, y-max => 100,
        sizing => Sizing.flex,
    );

    $panel.add: $top;
    $panel.add: $mid;
    $panel.add: $bot;

    my $out = render-to-string($panel, :$rows, :$cols);
    print $out;
}
