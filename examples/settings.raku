#!/usr/bin/env raku
#
# settings.raku — A settings form demonstrating every input widget.
#
# Demonstrates:
#   - TextInput, MultiLineInput, Checkbox, RadioGroup, Select, Button
#   - Border, VBox, HBox for layout
#   - Plain Modal (about dialog) and ConfirmModal (unsaved changes)
#   - A computed subscription: the Save button is enabled only when the
#     form is valid (name non-empty)
#   - The canonical pattern: widget -> Supply -> app code dispatches to store
#
# Run with:  raku -I lib examples/settings.raku

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Widget::Text;
use Selkie::Widget::TextInput;
use Selkie::Widget::MultiLineInput;
use Selkie::Widget::Button;
use Selkie::Widget::Checkbox;
use Selkie::Widget::RadioGroup;
use Selkie::Widget::Select;
use Selkie::Widget::Border;
use Selkie::Widget::Modal;
use Selkie::Widget::ConfirmModal;
use Selkie::Sizing;
use Selkie::Style;

my $app = Selkie::App.new;

# --- Store handlers --------------------------------------------------------

$app.store.register-handler('app/init', -> $st, %ev {
    (db => {
        form => {
            name         => '',
            bio          => '',
            notifications => True,
            density      => 0,        # 0=compact, 1=comfortable, 2=spacious
            theme        => 0,        # 0=auto, 1=light, 2=dark
            dirty        => False,    # has user changed anything?
        },
        status => 'Ready',
    },);
});

# A single generic handler for field updates keeps the example short.
# In a larger app you'd split per-field when each has business logic.
$app.store.register-handler('form/set-field', -> $st, %ev {
    my $field = %ev<field>;
    my $value = %ev<value>;
    (db => {
        form => { $field => $value, dirty => True },
    },);
});

$app.store.register-handler('form/save', -> $st, %ev {
    # In a real app this would persist somewhere. We just mark clean.
    (db => {
        form   => { dirty => False },
        status => "Saved '{$st.get-in('form', 'name')}'",
    },);
});

$app.store.register-handler('form/reset', -> $st, %ev {
    (db => {
        form => {
            name          => '',
            bio           => '',
            notifications => True,
            density       => 0,
            theme         => 0,
            dirty         => False,
        },
        status => 'Reset',
    },);
});

# --- Widget tree -----------------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

# Title bar
$root.add: Selkie::Widget::Text.new(
    text   => '  Settings  —  Tab cycles focus, Ctrl+S save, Ctrl+H about, Ctrl+Q quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# --- Form fields ----------------------------------------------------------

# Each field lives inside a VBox with a label Text + the input, wrapped in
# a Border that highlights when a descendant has focus.

sub labelled(Str $label, Selkie::Widget $input, Int $height = 3 --> Selkie::Widget::Border) {
    my $inner = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $inner.add: Selkie::Widget::Text.new(
        text   => $label,
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x999999),
    );
    $inner.add($input);
    my $border = Selkie::Widget::Border.new(sizing => Sizing.fixed($height));
    $border.set-content($inner);
    $border;
}

# Name (TextInput)
my $name-input = Selkie::Widget::TextInput.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Your display name',
);
$root.add(labelled('Name', $name-input, 4));

# Bio (MultiLineInput)
my $bio-input = Selkie::Widget::MultiLineInput.new(
    sizing      => Sizing.fixed(3),
    max-lines   => 3,
    placeholder => 'A short bio... (Ctrl+Enter to insert newline, field submits on blur)',
);
$root.add(labelled('Bio', $bio-input, 6));

# Notifications (Checkbox)
my $notif = Selkie::Widget::Checkbox.new(
    label  => 'Enable notifications',
    sizing => Sizing.fixed(1),
);
$root.add(labelled('Preferences', $notif, 4));

# Density (RadioGroup)
my $density = Selkie::Widget::RadioGroup.new(sizing => Sizing.fixed(3));
$density.set-items(<Compact Comfortable Spacious>);
$root.add(labelled('Density', $density, 6));

# Theme (Select)
my $theme-select = Selkie::Widget::Select.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Choose a theme',
);
$theme-select.set-items(<Auto Light Dark>);
$root.add(labelled('Theme', $theme-select, 4));

# Button row
my $button-row = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
my $save   = Selkie::Widget::Button.new(label => 'Save',  sizing => Sizing.flex);
my $reset  = Selkie::Widget::Button.new(label => 'Reset', sizing => Sizing.flex);
$button-row.add($save);
$button-row.add($reset);
$root.add($button-row);

# Status bar
my $status = Selkie::Widget::Text.new(
    text   => '',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x888888, italic => True),
);
$root.add($status);

# --- Dispatch wiring ------------------------------------------------------

$name-input.on-change.tap: -> $v {
    $app.store.dispatch('form/set-field', field => 'name', value => $v);
};
$bio-input.on-change.tap: -> $v {
    $app.store.dispatch('form/set-field', field => 'bio', value => $v);
};
$notif.on-change.tap: -> $v {
    $app.store.dispatch('form/set-field', field => 'notifications', value => $v);
};
$density.on-change.tap: -> $v {
    $app.store.dispatch('form/set-field', field => 'density', value => $v);
};
$theme-select.on-change.tap: -> $v {
    $app.store.dispatch('form/set-field', field => 'theme', value => $v);
};

$save.on-press.tap: -> $ {
    if ($app.store.get-in('form', 'name') // '').chars > 0 {
        $app.store.dispatch('form/save');
        $app.toast('Settings saved');
        $app.focus($name-input);   # nudge focus back so typing keeps working
    }
};

$reset.on-press.tap: -> $ {
    if $app.store.get-in('form', 'dirty') {
        show-reset-confirm();
    } else {
        $app.store.dispatch('form/reset');
        $app.focus($name-input);
    }
};

sub show-reset-confirm() {
    my $cm = Selkie::Widget::ConfirmModal.new;
    $cm.build(
        title     => 'Reset form',
        message   => 'Discard unsaved changes?',
        yes-label => 'Reset',
        no-label  => 'Cancel',
    );
    $cm.on-result.tap: -> Bool $confirmed {
        $app.close-modal;
        if $confirmed {
            $app.store.dispatch('form/reset');
        }
        $app.focus($name-input);
    };
    $app.show-modal($cm.modal);
    $app.focus($cm.no-button);
}

# --- Subscriptions --------------------------------------------------------

# Computed subscription: derive a human-readable form status from the
# underlying fields. The status bar text updates whenever validity or
# dirty-ness changes — with no direct coupling between widgets.
$app.store.subscribe-with-callback(
    'form-summary',
    -> $s {
        my $name  = ($s.get-in('form', 'name') // '').Str;
        my $dirty = $s.get-in('form', 'dirty') // False;
        if $name.chars == 0 {
            '  ⚠  Enter a name to enable Save';
        } elsif $dirty {
            "  ● Unsaved changes for '$name' — Ctrl+S to save";
        } else {
            "  ✓ '$name' saved";
        }
    },
    -> $text { $status.set-text($text) },
    $status,
);

# Sync each input back from the store. This is what makes "Reset" actually
# clear the visible inputs — and it works whether the change came from the
# user typing or from a programmatic dispatch. The "silent" setters avoid
# the loop where the input would re-emit the value into the same store path.
$app.store.subscribe-with-callback(
    'sync-name',
    -> $s { ($s.get-in('form', 'name') // '').Str },
    -> $v { $name-input.set-text-silent($v) if $name-input.text ne $v },
    $name-input,
);
$app.store.subscribe-with-callback(
    'sync-bio',
    -> $s { ($s.get-in('form', 'bio') // '').Str },
    -> $v { $bio-input.set-text-silent($v) if $bio-input.text ne $v },
    $bio-input,
);
$app.store.subscribe-with-callback(
    'sync-notif',
    -> $s { $s.get-in('form', 'notifications') // True },
    # Checkbox.set-checked short-circuits on no-change, so it's safe to
    # call unconditionally. Same applies to RadioGroup/Select select-index.
    -> Bool $v { $notif.set-checked($v) },
    $notif,
);
$app.store.subscribe-with-callback(
    'sync-density',
    -> $s { ($s.get-in('form', 'density') // 0).Int },
    -> Int $v { $density.select-index($v) },
    $density,
);
$app.store.subscribe-with-callback(
    'sync-theme',
    -> $s { ($s.get-in('form', 'theme') // 0).Int },
    -> Int $v { $theme-select.select-index($v) },
    $theme-select,
);

# --- Global keybinds ------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.on-key('ctrl+s', -> $ {
    if ($app.store.get-in('form', 'name') // '').chars > 0 {
        $app.store.dispatch('form/save');
        $app.toast('Settings saved');
    }
});
# Note: bare '?' would be eaten by whichever input has focus, so the help
# binding has to be modified.
$app.on-key('ctrl+h', -> $ { show-about() });

sub show-about() {
    my $modal = Selkie::Widget::Modal.new(
        width-ratio  => 0.5,
        height-ratio => 0.3,
    );
    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);
    $content.add: Selkie::Widget::Text.new(
        text   => '  About this example',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    );
    $content.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));
    $content.add: Selkie::Widget::Text.new(
        text   => '  A settings form demonstrating every input widget.',
        sizing => Sizing.fixed(1),
    );
    $content.add: Selkie::Widget::Text.new(
        text   => '  Press Esc to close.',
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x888888, italic => True),
    );
    $content.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    my $ok = Selkie::Widget::Button.new(label => 'OK', sizing => Sizing.fixed(1));
    $content.add($ok);

    $modal.set-content($content);

    $ok.on-press.tap:  -> $ { $app.close-modal };
    $modal.on-close.tap: -> $ { $app.close-modal };

    $app.show-modal($modal);
    $app.focus($ok);
}

# --- Go -------------------------------------------------------------------

$app.store.dispatch('app/init');
$app.store.tick;

$app.focus($name-input);
$app.run;
