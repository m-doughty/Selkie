#!/usr/bin/env raku
#
# counter.raku — The smallest Selkie app that follows the store pattern.
#
# Demonstrates:
#   - App lifecycle (add-screen, switch-screen, focus, run)
#   - VBox layout with mixed fixed + flex sizing
#   - A store handler that returns a (db => {...}) effect — no assoc-in
#   - A subscription that re-renders the Text widget when state changes
#   - Global keybind for quit
#
# Run with:  raku -I lib examples/counter.raku

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::Button;
use Selkie::Style;
use Selkie::Sizing;

my $app = Selkie::App.new;

# --- State handlers --------------------------------------------------------
# Handlers are pure: (store, payload) -> effects. The `db` effect is a deep
# merge into the state tree — never mutate the store directly.

$app.store.register-handler('app/init', -> $st, %ev {
    (db => { count => 0 },);
});

$app.store.register-handler('counter/inc', -> $st, %ev {
    my $current = $st.get-in('count') // 0;
    (db => { count => $current + 1 },);
});

$app.store.register-handler('counter/dec', -> $st, %ev {
    my $current = $st.get-in('count') // 0;
    (db => { count => $current - 1 },);
});

$app.store.register-handler('counter/reset', -> $st, %ev {
    (db => { count => 0 },);
});

# --- Widget tree ----------------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

# Title
$root.add: Selkie::Widget::Text.new(
    text   => '  Selkie Counter  —  Tab switches focus, Ctrl+Q quits',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Spacer
$root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

# Centered count display
my $count-text = Selkie::Widget::Text.new(
    text   => '0',
    sizing => Sizing.fixed(3),
    style  => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
);
$root.add($count-text);

# Button row
my $buttons = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $dec    = Selkie::Widget::Button.new(label => '  −  ', sizing => Sizing.flex);
my $reset  = Selkie::Widget::Button.new(label => 'Reset', sizing => Sizing.flex);
my $inc    = Selkie::Widget::Button.new(label => '  +  ', sizing => Sizing.flex);
$buttons.add($dec);
$buttons.add($reset);
$buttons.add($inc);
$root.add($buttons);

$root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

# --- Wire buttons to dispatch ---------------------------------------------
# Widgets emit on Supplies; the app-level code is where store events are
# dispatched. This keeps widgets reusable and store-agnostic.

$dec.on-press.tap:   -> $ { $app.store.dispatch('counter/dec') };
$inc.on-press.tap:   -> $ { $app.store.dispatch('counter/inc') };
$reset.on-press.tap: -> $ { $app.store.dispatch('counter/reset') };

# --- Subscription ---------------------------------------------------------
# When `count` changes, recompute the display string and update the widget.
# Using subscribe-with-callback because we need the value to drive a method
# call (set-text), not just mark a widget dirty.

$app.store.subscribe-with-callback(
    'count-display',
    -> $s { ($s.get-in('count') // 0).Str },
    -> $text {
        # Pad with spaces + center-ish for a bigger visual
        $count-text.set-text('');   # clear
        $count-text.set-text("       Count: $text");
    },
    $count-text,
);

# Initial state — dispatched and ticked synchronously so the first render
# sees a populated store.
$app.store.dispatch('app/init');
$app.store.tick;

# --- Global keybinds ------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });

# --- Go -------------------------------------------------------------------

$app.focus($inc);       # start with + focused
$app.run;
