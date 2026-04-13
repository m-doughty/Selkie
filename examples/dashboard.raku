#!/usr/bin/env raku
#
# dashboard.raku — A tabbed dashboard showcasing the newer widgets.
#
# Demonstrates:
#   - TabBar at the top, switching between three tabbed views
#   - Table with sortable columns, custom cell rendering, and row activation
#   - Spinner animating in the footer while a mock "polling" job runs
#   - CommandPalette bound to Ctrl+P for quick actions
#   - Content-swap via Border.set-content(:!destroy) so each tab's widget
#     retains its state across tab changes
#   - Toast notifications for feedback
#
# Run with:  raku -I lib examples/dashboard.raku

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::TextStream;
use Selkie::Widget::Border;
use Selkie::Widget::TabBar;
use Selkie::Widget::Table;
use Selkie::Widget::Spinner;
use Selkie::Widget::CommandPalette;
use Selkie::Widget::ListView;
use Selkie::Sizing;
use Selkie::Style;

my $app = Selkie::App.new;

# --- Store handlers --------------------------------------------------------

$app.store.register-handler('app/init', -> $st, %ev {
    (db => {
        active-tab => 'servers',
        servers    => seed-servers(),
        tasks      => seed-tasks(),
        polling    => True,
    },);
});

$app.store.register-handler('tab/select', -> $st, %ev {
    (db => { active-tab => %ev<name> },);
});

$app.store.register-handler('polling/toggle', -> $st, %ev {
    (db => { polling => !($st.get-in('polling') // False) },);
});

$app.store.register-handler('servers/refresh', -> $st, %ev {
    (db => { servers => seed-servers(:jitter) },);
});

$app.store.register-handler('task/toggle', -> $st, %ev {
    my $idx = %ev<index>;
    my @tasks = ($st.get-in('tasks') // []).Array;
    if $idx.defined && $idx < @tasks.elems {
        @tasks[$idx] = %( |@tasks[$idx], done => !@tasks[$idx]<done> );
    }
    (db => { tasks => @tasks },);
});

# --- Seed data -------------------------------------------------------------

sub seed-servers(Bool :$jitter) {
    my @rows = (
        { host => 'api-1.example.com',  status => 'up',   uptime => 87_200,  latency => 12 },
        { host => 'api-2.example.com',  status => 'up',   uptime => 12_350,  latency => 18 },
        { host => 'db-primary',         status => 'up',   uptime => 432_100, latency => 3  },
        { host => 'db-replica-1',       status => 'up',   uptime => 418_900, latency => 4  },
        { host => 'cache-1',            status => 'down', uptime => 0,       latency => 0  },
        { host => 'queue-worker-1',     status => 'up',   uptime => 56_700,  latency => 8  },
        { host => 'queue-worker-2',     status => 'warn', uptime => 56_700,  latency => 142 },
        { host => 'batch-runner',       status => 'up',   uptime => 201_400, latency => 22 },
    );
    if $jitter {
        # Small perturbation so refreshes feel alive without thrashing the
        # table redraw — refreshes still cascade through the widget tree.
        @rows = @rows.map({
            my $l = .<latency>;
            %(|$_, latency => $l == 0 ?? 0 !! $l + ((-1, 0, 1).pick));
        }).Array;
    }
    @rows;
}

sub seed-tasks() {
    [
        { title => 'Upgrade Rakudo to 2026.03', done => True  },
        { title => 'Publish Selkie 0.2.0',       done => False },
        { title => 'Write dashboard example',    done => False },
        { title => 'Record demo GIF',            done => False },
        { title => 'Update website landing',     done => False },
    ];
}

# --- Formatting helpers ----------------------------------------------------

sub human-uptime(Int $s --> Str) {
    given $s {
        when 0              { '—' }
        when * < 60         { "{$s}s" }
        when * < 3600       { "{($s / 60).floor}m" }
        when * < 86_400     { "{($s / 3600).floor}h" }
        default             { "{($s / 86_400).floor}d" }
    }
}

sub status-cell(Str $s --> Str) {
    given $s {
        when 'up'   { '✓ up'   }
        when 'down' { '✗ down' }
        when 'warn' { '⚠ warn' }
        default     { $s }
    }
}

# --- Widget tree -----------------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

# Title
$root.add: Selkie::Widget::Text.new(
    text   => '  Selkie Dashboard  —  Tab cycles focus, Ctrl+P palette, Ctrl+Q quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# TabBar
my $tabs = Selkie::Widget::TabBar.new(sizing => Sizing.fixed(1));
$tabs.add-tab(name => 'servers', label => 'Servers');
$tabs.add-tab(name => 'tasks',   label => 'Tasks');
$tabs.add-tab(name => 'logs',    label => 'Logs');
$root.add($tabs);

# Content area: a Border whose content is swapped per-tab.
my $content-border = Selkie::Widget::Border.new(sizing => Sizing.flex);
$root.add($content-border);

# --- Pre-build the per-tab widgets (kept alive across tab switches via
# --- set-content(:!destroy)) ------------------------------------------------

# Servers: a Table
my $servers-table = Selkie::Widget::Table.new(sizing => Sizing.flex);
$servers-table.add-column(
    name => 'host', label => 'Host',
    sizing => Sizing.flex(2), :sortable,
);
$servers-table.add-column(
    name => 'status', label => 'Status',
    sizing => Sizing.fixed(8), :sortable,
    render => &status-cell,
);
$servers-table.add-column(
    name     => 'uptime', label => 'Uptime',
    sizing   => Sizing.fixed(8), :sortable,
    render   => -> $s { human-uptime($s) },
    sort-key => -> $s { $s },
);
$servers-table.add-column(
    name     => 'latency', label => 'Latency',
    sizing   => Sizing.fixed(10), :sortable,
    render   => -> $ms { $ms == 0 ?? '—' !! "{$ms}ms" },
    sort-key => -> $ms { $ms },
);

# Tasks: a ListView of "[x] title" strings (keeping the demo varied)
my $tasks-list = Selkie::Widget::ListView.new(sizing => Sizing.flex);

# Logs: a TextStream that we append mock entries to on each poll
my $logs-stream = Selkie::Widget::TextStream.new(sizing => Sizing.flex);
$logs-stream.append('--- dashboard started ---');

# --- Footer: Spinner + status text -----------------------------------------

my $footer = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $spinner = Selkie::Widget::Spinner.new(
    sizing   => Sizing.fixed(2),
    frames   => Selkie::Widget::Spinner::BRAILLE,
    interval => 0.15,    # 6-7 fps — calm but clearly alive
);
my $status = Selkie::Widget::Text.new(
    text   => '',
    sizing => Sizing.flex,
    style  => Selkie::Style.new(fg => 0x888888),
);
$footer.add($spinner);
$footer.add($status);
$root.add($footer);

# --- Subscriptions ---------------------------------------------------------

# Swap content when active tab changes. Uses :!destroy so widget state
# (scroll position, table cursor) is preserved across tab switches.
$app.store.subscribe-with-callback(
    'active-tab-content',
    -> $s { $s.get-in('active-tab') // 'servers' },
    -> Str $name {
        given $name {
            when 'servers' {
                $content-border.set-title('Servers');
                $content-border.set-content($servers-table, :!destroy);
            }
            when 'tasks' {
                $content-border.set-title('Tasks');
                $content-border.set-content($tasks-list, :!destroy);
            }
            when 'logs' {
                $content-border.set-title('Logs');
                $content-border.set-content($logs-stream, :!destroy);
            }
        }
    },
    $content-border,
);

# Keep the TabBar's active tab in sync with the store (enables programmatic
# tab switches via the command palette).
$app.store.subscribe-with-callback(
    'tab-sync',
    -> $s { $s.get-in('active-tab') // 'servers' },
    -> Str $name { $tabs.set-active-name-silent($name) },
    $tabs,
);

# Server rows → table
$app.store.subscribe-with-callback(
    'server-rows',
    -> $s { ($s.get-in('servers') // []).List },
    -> @rows { $servers-table.set-rows(@rows) },
    $servers-table,
);

# Task rows → list
$app.store.subscribe-with-callback(
    'task-rows',
    -> $s { ($s.get-in('tasks') // []).List },
    -> @tasks {
        my @items = @tasks.map(-> %t {
            my $mark = %t<done> ?? '[x]' !! '[ ]';
            "$mark {%t<title>}"
        });
        $tasks-list.set-items(@items);
    },
    $tasks-list,
);

# Footer status reflects polling state + row counts
$app.store.subscribe-with-callback(
    'footer-text',
    -> $s {
        my $polling = $s.get-in('polling') // False;
        my $n-servers = ($s.get-in('servers') // []).elems;
        my $indicator = $polling ?? 'polling' !! 'paused';
        "  $indicator  —  monitoring $n-servers servers";
    },
    -> $text { $status.set-text($text) },
    $status,
);

# --- Wiring ----------------------------------------------------------------

$tabs.on-tab-selected.tap: -> Str $name {
    $app.store.dispatch('tab/select', :$name);
};

$servers-table.on-activate.tap: -> UInt $idx {
    my $row = $servers-table.row-at($idx);
    $app.toast("Host: {$row<host>} — {$row<status>}") if $row;
};

# Enter on the tasks list toggles the done/undone state. ListView emits
# the selected STRING on on-activate; we read the cursor for the index.
$tasks-list.on-activate.tap: -> $ {
    $app.store.dispatch('task/toggle', index => $tasks-list.cursor);
};

# Sortable column cycle: press 's' with the table focused to cycle through
# the sortable columns.
$servers-table.on-key: 's', -> $ {
    my @sortable = $servers-table.columns.grep(*.sortable);
    if @sortable {
        my $current = $servers-table.sort-column;
        my $idx = $current.defined
            ?? (@sortable.first(*.name eq $current, :k) // -1)
            !! -1;
        my $next = @sortable[($idx + 1) mod @sortable.elems];
        $servers-table.sort-by($next.name);
    }
};

# --- Command palette -------------------------------------------------------

my $palette = Selkie::Widget::CommandPalette.new;
$palette.add-command(label => 'Go to Servers', -> {
    $app.store.dispatch('tab/select', name => 'servers');
});
$palette.add-command(label => 'Go to Tasks', -> {
    $app.store.dispatch('tab/select', name => 'tasks');
});
$palette.add-command(label => 'Go to Logs', -> {
    $app.store.dispatch('tab/select', name => 'logs');
});
$palette.add-command(label => 'Refresh servers', -> {
    $app.store.dispatch('servers/refresh');
    $app.toast('Servers refreshed');
});
$palette.add-command(label => 'Toggle polling', -> {
    $app.store.dispatch('polling/toggle');
});
$palette.add-command(label => 'Quit', -> { $app.quit });

my $palette-modal = $palette.build;

$palette.on-command.tap: -> $cmd {
    $app.close-modal;
    $cmd.action.();
};

$app.on-key('ctrl+p', -> $ {
    $palette.reset;
    $app.show-modal($palette-modal);
    $app.focus($palette.focusable-widget);
});

# --- Mock "polling" job ----------------------------------------------------
# Every N frames, if polling is enabled, append a log line and refresh.
# This is the reason we have the spinner animating in the footer.

my UInt $frame = 0;
$app.on-frame: {
    $spinner.tick;
    $frame++;
    # Poll every ~3 seconds (60fps × 180 frames) when polling is enabled.
    # Each poll appends a log line AND refreshes the servers table.
    if $frame %% 180 && ($app.store.get-in('polling') // False) {
        $logs-stream.append(
            sprintf '[%s]  polled %d servers',
                    DateTime.now.hh-mm-ss, ($app.store.get-in('servers') // []).elems,
        );
        $app.store.dispatch('servers/refresh');
    }
};

# --- Global keybinds -------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.on-key('ctrl+r', -> $ {
    $app.store.dispatch('servers/refresh');
    $app.toast('Refreshed');
});
$app.on-key('ctrl+space', -> $ {
    $app.store.dispatch('polling/toggle');
});

# --- Go --------------------------------------------------------------------

$app.store.dispatch('app/init');
$app.store.tick;

$app.focus($tabs);
$app.run;
