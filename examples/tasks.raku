#!/usr/bin/env raku
#
# tasks.raku — Todo list with multiple screens.
#
# Demonstrates:
#   - ListView (selectable string list with cursor)
#   - TextInput for adding new tasks
#   - Checkbox to drive "show completed" filter
#   - ConfirmModal for delete confirmation
#   - Toast for transient feedback
#   - ScreenManager: switch between list screen and stats screen via Ctrl+T
#   - Path subscription drives the list contents
#   - The `dispatch` effect chains events (delete -> reload)
#
# Run with:  raku -I lib examples/tasks.raku

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::TextInput;
use Selkie::Widget::Checkbox;
use Selkie::Widget::ListView;
use Selkie::Widget::Border;
use Selkie::Widget::ConfirmModal;
use Selkie::Sizing;
use Selkie::Style;

my $app = Selkie::App.new;

# --- Store handlers -------------------------------------------------------
#
# Tasks are stored as { id => Int, text => Str, done => Bool }.
# `next-id` is a simple monotonic counter for new tasks.

$app.store.register-handler('app/init', -> $st, %ev {
    (db => {
        tasks         => [
            { id => 1, text => 'Read the Selkie docs',     done => True  },
            { id => 2, text => 'Build a tiny TUI',          done => False },
            { id => 3, text => 'Brag about it on Mastodon', done => False },
        ],
        next-id       => 4,
        show-complete => True,
    },);
});

$app.store.register-handler('task/add', -> $st, %ev {
    my $text = (%ev<text> // '').trim;
    if $text.chars == 0 {
        ();
    } else {
        my @tasks = ($st.get-in('tasks') // []).Array;
        my $id    = $st.get-in('next-id') // 1;
        @tasks.push({ :$id, :$text, done => False });
        (db => {
            tasks   => @tasks,
            next-id => $id + 1,
        },);
    }
});

$app.store.register-handler('task/toggle', -> $st, %ev {
    my $id    = %ev<id>;
    my @tasks = ($st.get-in('tasks') // []).Array;
    @tasks = @tasks.map(-> %t {
        %t<id> == $id ?? %( |%t, done => !%t<done> ) !! %t
    }).Array;
    (db => { tasks => @tasks },);
});

$app.store.register-handler('task/delete', -> $st, %ev {
    my $id    = %ev<id>;
    my @tasks = ($st.get-in('tasks') // []).Array;
    @tasks = @tasks.grep(*<id> != $id).Array;
    (db => { tasks => @tasks },);
});

$app.store.register-handler('filter/toggle', -> $st, %ev {
    my $current = $st.get-in('show-complete') // True;
    (db => { show-complete => !$current },);
});

# --- LIST SCREEN ----------------------------------------------------------

my $list-root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('list', $list-root);

# Title bar
$list-root.add: Selkie::Widget::Text.new(
    text   => '  Tasks  —  Tab focus list, ↑↓ navigate, Enter toggle, d delete, Ctrl+T stats, Ctrl+Q quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Filter checkbox
my $filter = Selkie::Widget::Checkbox.new(
    label  => 'Show completed',
    sizing => Sizing.fixed(1),
);
$filter.set-checked(True);
$list-root.add($filter);

# Task list (in a Border so focus is visible)
my $list = Selkie::Widget::ListView.new(sizing => Sizing.flex);
my $list-border = Selkie::Widget::Border.new(title => 'Tasks', sizing => Sizing.flex);
$list-border.set-content($list);
$list-root.add($list-border);

# Add-task input
my $add-input = Selkie::Widget::TextInput.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Add a task — press Enter to submit',
);
my $add-border = Selkie::Widget::Border.new(title => 'New', sizing => Sizing.fixed(3));
$add-border.set-content($add-input);
$list-root.add($add-border);

# --- STATS SCREEN ---------------------------------------------------------

my $stats-root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('stats', $stats-root);

$stats-root.add: Selkie::Widget::Text.new(
    text   => '  Stats  —  Ctrl+T returns to list, Ctrl+Q quits',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);
$stats-root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

my $stats-text = Selkie::Widget::Text.new(
    text   => '',
    sizing => Sizing.fixed(5),
    style  => Selkie::Style.new(fg => 0xEEEEEE),
);
$stats-root.add($stats-text);

$stats-root.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

# --- Wiring ---------------------------------------------------------------

# Maintain a parallel array of visible task ids so list cursor positions
# map back to the underlying task. Updated by the list-render subscription.
my @visible-ids;

# Helper: which task id is at the cursor?
sub current-task-id() {
    @visible-ids[$list.cursor] // Int;
}

$add-input.on-submit.tap: -> $text {
    if $text.chars > 0 {
        $app.store.dispatch('task/add', :$text);
        $add-input.clear;
    }
};

$filter.on-change.tap: -> $ {
    $app.store.dispatch('filter/toggle');
};

$list.on-activate.tap: -> $ {
    with current-task-id() -> $id {
        $app.store.dispatch('task/toggle', :$id);
    }
};

# 'd' on the list view triggers delete confirmation
$list.on-key('d', -> $ {
    with current-task-id() -> $id {
        my @tasks = $app.store.get-in('tasks') // [];
        with @tasks.first(*<id> == $id) -> $task {
            my $cm = Selkie::Widget::ConfirmModal.new;
            $cm.build(
                title     => 'Delete task',
                message   => "Delete '{$task<text>}'?",
                yes-label => 'Delete',
                no-label  => 'Cancel',
            );
            $cm.on-result.tap: -> Bool $confirmed {
                $app.close-modal;
                if $confirmed {
                    $app.store.dispatch('task/delete', :$id);
                    $app.toast('Task deleted');
                }
            };
            $app.show-modal($cm.modal);
            $app.focus($cm.no-button);
        }
    }
});

# --- Subscriptions --------------------------------------------------------

# Build the visible-ids array + list items from filtered tasks.
$app.store.subscribe-with-callback(
    'task-list',
    -> $s {
        my @tasks = ($s.get-in('tasks') // []).Array;
        my $show  = $s.get-in('show-complete') // True;
        $show ?? @tasks !! @tasks.grep({ !$_<done> }).Array;
    },
    -> @tasks {
        @visible-ids = @tasks.map(*<id>).Array;
        my @items = @tasks.map(-> %t {
            my $marker = %t<done> ?? '[x]' !! '[ ]';
            "$marker {%t<text>}"
        });
        $list.set-items(@items);
    },
    $list,
);

# Stats screen text — recomputes whenever tasks change.
$app.store.subscribe-with-callback(
    'stats-text',
    -> $s {
        my @tasks = ($s.get-in('tasks') // []).Array;
        my $total = @tasks.elems;
        my $done  = @tasks.grep(*<done>).elems;
        my $pct   = $total == 0 ?? 0 !! (100 * $done / $total).round.Int;
        join "\n",
            "  Total tasks: $total",
            "  Completed:   $done",
            "  Remaining:   {$total - $done}",
            "  Progress:    $pct%";
    },
    -> $text { $stats-text.set-text($text) },
    $stats-text,
);

# --- Global keybinds ------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });

# Toggle between screens. We only update focus when arriving at a screen
# whose focus target exists.
$app.on-key('ctrl+t', -> $ {
    if $app.screen-manager.active-screen eq 'list' {
        $app.switch-screen('stats');
    } else {
        $app.switch-screen('list');
        $app.focus($add-input);
    }
});

# --- Go -------------------------------------------------------------------

$app.store.dispatch('app/init');
$app.store.tick;

$app.switch-screen('list');
$app.focus($add-input);
$app.run;
