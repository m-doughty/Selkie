#!/usr/bin/env raku
#
# job-runner.raku — Simulate a multi-step background job.
#
# Demonstrates:
#   - ProgressBar in determinate mode (driven by store state)
#   - ProgressBar in indeterminate mode (animated by frame callback tick)
#   - TextStream as a live log
#   - The `async` store effect: kicks off background work, dispatches
#     follow-up events (`job/step` and `job/done`) when complete
#   - The `dispatch` effect: handlers chaining further events
#   - Frame callback driving widget animation
#
# Run with:  raku -I lib examples/job-runner.raku

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::Button;
use Selkie::Widget::ProgressBar;
use Selkie::Widget::TextStream;
use Selkie::Widget::Border;
use Selkie::Sizing;
use Selkie::Style;

my $app = Selkie::App.new;

# How many simulated steps in a "job"
constant TOTAL-STEPS = 8;

# --- Store handlers -------------------------------------------------------

$app.store.register-handler('app/init', -> $st, %ev {
    (db => {
        running       => False,
        step          => 0,
        total         => TOTAL-STEPS,
    },);
});

$app.store.register-handler('job/start', -> $st, %ev {
    if $st.get-in('running') {
        ();   # already running, ignore
    } else {
        # Kick off step 1 immediately, then schedule the rest via async
        (
            db => { running => True, step => 0 },
            dispatch => { event => 'job/step' },
        );
    }
});

$app.store.register-handler('job/step', -> $st, %ev {
    my $step  = ($st.get-in('step') // 0) + 1;
    my $total = $st.get-in('total') // TOTAL-STEPS;
    if $step >= $total {
        (
            db       => { step => $step },
            dispatch => { event => 'job/done' },
        );
    } else {
        (
            db    => { step => $step },
            # async effect: do "work" off the main thread, then dispatch.
            # In a real app, &work would be the actual unit of work.
            async => {
                work       => -> { sleep 0.4; "step-$step output" },
                on-success => 'job/step-complete',
                on-failure => 'job/error',
            },
        );
    }
});

# Whenever a step's async work resolves, schedule the next step.
$app.store.register-handler('job/step-complete', -> $st, %ev {
    (dispatch => { event => 'job/step' },);
});

$app.store.register-handler('job/done', -> $st, %ev {
    (db => { running => False },);
});

$app.store.register-handler('job/error', -> $st, %ev {
    (db => { running => False },);
});

# --- Widget tree ----------------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

$root.add: Selkie::Widget::Text.new(
    text   => '  Job Runner  —  s: start, Ctrl+Q: quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Progress section: indeterminate spinner + determinate progress
my $progress-vbox = Selkie::Layout::VBox.new(sizing => Sizing.fixed(4));

my $spinner = Selkie::Widget::ProgressBar.new(
    indeterminate    => True,
    show-percentage  => False,
    frames-per-step  => 4,
    sizing           => Sizing.fixed(1),
);
$progress-vbox.add($spinner);

my $progress = Selkie::Widget::ProgressBar.new(
    sizing          => Sizing.fixed(1),
    show-percentage => True,
);
$progress-vbox.add($progress);

my $progress-border = Selkie::Widget::Border.new(title => 'Progress', sizing => Sizing.fixed(6));
$progress-border.set-content($progress-vbox);
$root.add($progress-border);

# Log
my $log = Selkie::Widget::TextStream.new(
    sizing    => Sizing.flex,
    max-lines => 1000,
);
my $log-border = Selkie::Widget::Border.new(title => 'Log', sizing => Sizing.flex);
$log-border.set-content($log);
$root.add($log-border);

# Action button
my $start = Selkie::Widget::Button.new(label => 'Start job', sizing => Sizing.fixed(1));
$root.add($start);

# --- Wiring ---------------------------------------------------------------

$start.on-press.tap: -> $ {
    $log.append('--- starting job ---');
    $app.store.dispatch('job/start');
};

$app.on-key('s', -> $ {
    $log.append('--- starting job ---');
    $app.store.dispatch('job/start');
});

# --- Subscriptions --------------------------------------------------------

# Progress fraction (determinate)
$app.store.subscribe-with-callback(
    'progress',
    -> $s {
        my $step  = $s.get-in('step')  // 0;
        my $total = $s.get-in('total') // 1;
        $total == 0 ?? 0.0 !! ($step / $total).Rat;
    },
    -> $frac { $progress.set-value($frac) },
    $progress,
);

# Each step transition emits a log line. Using subscribe-with-callback with
# the step number as the key — fires only when it actually changes.
$app.store.subscribe-with-callback(
    'log-step',
    -> $s { $s.get-in('step') // 0 },
    -> Int $step {
        if $step > 0 {
            my $total = $app.store.get-in('total') // TOTAL-STEPS;
            $log.append("  step $step / $total complete");
            if $step >= $total {
                $log.append('--- job done ---');
            }
        }
    },
    $log,
);

# Toggle the spinner's visual hint based on running state. The widget
# itself ticks each frame; we just stop or start it via show-percentage as
# a low-effort visual cue. (For a real app you'd add a widget-level method
# like `set-active(Bool)`; this keeps the example minimal.)
$app.store.subscribe-with-callback(
    'spinner-running',
    -> $s { $s.get-in('running') // False },
    -> Bool $running {
        $spinner.indeterminate = $running;
        $spinner.set-value(0.0) unless $running;
    },
    $spinner,
);

# --- Frame callback -------------------------------------------------------
# The spinner needs ticking each frame to advance its bouncing animation.

$app.on-frame: { $spinner.tick };

# --- Global keybinds ------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });

# --- Go -------------------------------------------------------------------

$app.store.dispatch('app/init');
$app.store.tick;

$log.append('Press s (or focus and Enter on the button) to start.');
$app.focus($start);
$app.run;
