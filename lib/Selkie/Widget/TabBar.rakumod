=begin pod

=head1 NAME

Selkie::Widget::TabBar - Horizontal tab strip integrated with ScreenManager

=head1 SYNOPSIS

=begin code :lang<raku>

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

=end code

=head1 DESCRIPTION

A one-line horizontal strip of named tabs. The active tab is
highlighted with the theme's C<text-highlight> slot; others render in
the default C<text> slot. Focusable — Left/Right arrows move the
active tab, C<Enter> fires C<on-tab-selected> (which you typically tap
to call C<$app.switch-screen>).

Tabs are identified by an opaque C<name> string and displayed as a
C<label>. The name is what's emitted on C<on-tab-selected> — choose
something that matches your registered screen names for a zero-effort
integration with C<Selkie::ScreenManager>.

C<TabBar> also has convenient integration with C<ScreenManager>: call
C<sync-to-app($app)> to make the active tab reflect C<$app.screen-manager.active-screen>
automatically via a store subscription.

=head1 EXAMPLES

=head2 Wiring to ScreenManager

The canonical pattern: one tab per screen, selection dispatches a
screen switch, and the bar keeps itself in sync if the screen changes
from elsewhere:

=begin code :lang<raku>

my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'inbox',  label => 'Inbox');
$tabs.add-tab(name => 'sent',   label => 'Sent');
$tabs.add-tab(name => 'drafts', label => 'Drafts');

$tabs.on-tab-selected.tap: -> Str $name {
    $app.switch-screen($name);
};

# Keep the bar's active tab in sync with whatever's actually showing
$tabs.sync-to-app($app);

=end code

=head2 Without ScreenManager

Tabs don't have to drive screen switches — you can use them as a
lightweight "mode" selector for a single screen's content:

=begin code :lang<raku>

my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'recent', label => 'Recent');
$tabs.add-tab(name => 'saved',  label => 'Saved');
$tabs.add-tab(name => 'all',    label => 'All');

$tabs.on-tab-selected.tap: -> Str $name {
    $app.store.dispatch('view/mode-changed', mode => $name);
};

=end code

=head1 SEE ALSO

=item L<Selkie::ScreenManager> — the multi-screen registry TabBar typically drives
=item L<Selkie::App> — screen-scoped keybinds complement per-tab views

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::TabBar does Selkie::Widget;

has @!tabs;                 # Array of { name => Str, label => Str }
has UInt $!active-idx = 0;
has Bool $!focused = False;
has Supplier $!select-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::TabBar) {
    %args<focusable> //= True;
    callwith(|%args);
}

#|( Register a tab. C<name> is the identifier (usually matches a
    screen name); C<label> is what's shown to the user. Tabs render
    in the order they're added. )
method add-tab(Str:D :$name!, Str:D :$label!) {
    @!tabs.push({ :$name, :$label });
    self.mark-dirty;
}

#| Remove a tab by name. If the removed tab was active, activation
#| falls to the tab that was to its left (or index 0).
method remove-tab(Str:D $name) {
    my $idx = @!tabs.first(*<name> eq $name, :k);
    return without $idx;
    @!tabs.splice($idx, 1);
    $!active-idx = ($!active-idx min (@!tabs.elems - 1)) max 0 if @!tabs;
    $!active-idx = 0 unless @!tabs;
    self.mark-dirty;
}

#| Remove all tabs.
method clear-tabs() {
    @!tabs = ();
    $!active-idx = 0;
    self.mark-dirty;
}

#| Tab name of the currently active tab, or C<Nil> if the bar is empty.
method active-name(--> Str) {
    return Str unless @!tabs;
    @!tabs[$!active-idx]<name>;
}

#| Index of the active tab.
method active-index(--> UInt) { $!active-idx }

#| Tab names in order.
method tab-names(--> List) { @!tabs.map(*<name>).List }

#|( Activate the tab with this name. No-op if the name isn't registered
    or already active. Emits C<on-tab-selected>. )
method select-by-name(Str:D $name) {
    my $idx = @!tabs.first(*<name> eq $name, :k);
    return without $idx;
    self!activate($idx);
}

#| Activate the tab at this index. No-op if already active or out of range.
method select-index(UInt $idx) {
    return unless @!tabs && $idx < @!tabs.elems;
    self!activate($idx);
}

method !activate(UInt $idx) {
    return if $idx == $!active-idx;
    $!active-idx = $idx;
    self.mark-dirty;
    $!select-supplier.emit(@!tabs[$idx]<name>);
}

#| Silently set the active index (no C<on-tab-selected> emit). Use from
#| a store subscription that syncs the bar to external state — prevents
#| feedback loops.
method set-active-name-silent(Str:D $name) {
    my $idx = @!tabs.first(*<name> eq $name, :k);
    return without $idx;
    return if $idx == $!active-idx;
    $!active-idx = $idx;
    self.mark-dirty;
}

#| Supply emitting the C<name> of the newly-active tab whenever the
#| user changes it (or a programmatic C<select-by-name> fires).
method on-tab-selected(--> Supply) { $!select-supplier.Supply }

#|( Install a store subscription that keeps this TabBar's active tab
    synced to C<$app.screen-manager.active-screen>. Makes the bar
    self-consistent: if you call C<$app.switch-screen(...)> elsewhere,
    the bar's highlight follows along. )
method sync-to-app($app) {
    my $bar = self;
    $bar.once-subscribe-computed("tabbar-sync-{self.WHICH}", -> $ {
        $app.screen-manager.active-screen // ''
    });
    # subscribe-computed only marks dirty; we want a side effect, so
    # also register a callback subscription:
    $app.store.subscribe-with-callback(
        "tabbar-sync-cb-{self.WHICH}",
        -> $ { $app.screen-manager.active-screen // '' },
        -> Str $name { $bar.set-active-name-silent($name) },
        $bar,
    );
}

method set-focused(Bool $f) {
    $!focused = $f;
    self.mark-dirty;
}

method is-focused(--> Bool) { $!focused }

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    return unless @!tabs;

    my $base = self.theme.text;
    my $hl   = self.theme.text-highlight;

    my UInt $x = 0;
    my UInt $w = self.cols;

    for @!tabs.kv -> $i, %tab {
        my $is-active = $i == $!active-idx;
        my $style = $is-active ?? $hl !! $base;
        self.apply-style($style);

        # Active tab gets brackets; inactive gets padding. Focused bar
        # further emphasises the active tab with bold.
        my $display = $is-active
            ?? "[ {%tab<label>} ]"
            !! "  {%tab<label>}  ";

        last if $x >= $w;
        my $fits = $w - $x;
        $display = $display.substr(0, $fits) if $display.chars > $fits;
        ncplane_putstr_yx(self.plane, 0, $x, $display);
        $x += $display.chars;
    }

    self.clear-dirty;
}

method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $!focused;

    if $ev.event-type ~~ KeyEvent {
        given $ev.id {
            when NCKEY_LEFT {
                if $!active-idx > 0 {
                    self!activate($!active-idx - 1);
                }
                return True;
            }
            when NCKEY_RIGHT {
                if $!active-idx + 1 < @!tabs.elems {
                    self!activate($!active-idx + 1);
                }
                return True;
            }
            when NCKEY_HOME {
                self!activate(0) if @!tabs;
                return True;
            }
            when NCKEY_END {
                self!activate(@!tabs.elems - 1) if @!tabs;
                return True;
            }
            when NCKEY_ENTER | NCKEY_SPACE {
                # Re-emit even if unchanged — useful when tapping "activate"
                # when the bar itself didn't move. Skipped if empty.
                if @!tabs {
                    $!select-supplier.emit(@!tabs[$!active-idx]<name>);
                }
                return True;
            }
        }
    }

    self!check-keybinds($ev);
}
