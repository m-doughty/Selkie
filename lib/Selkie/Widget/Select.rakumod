=begin pod

=head1 NAME

Selkie::Widget::Select - Compact dropdown picker

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::Select;
use Selkie::Sizing;

my $select = Selkie::Widget::Select.new(
    sizing      => Sizing.fixed(1),
    placeholder => 'Choose a model',
    max-visible => 8,
);
$select.set-items(<gpt-4 claude-opus local-model>);
$select.on-change.tap: -> UInt $idx {
    say $select.selected-value;
};

=end code

=head1 DESCRIPTION

A single-line control showing the currently selected value with a
C<▼> marker. C<Enter> or C<Space> opens a dropdown list as a child
plane rendered on top of the surrounding layout. Esc cancels; Enter
commits the highlighted option.

While open, the Select acts as a local focus trap — arrow keys and
Enter navigate the dropdown, not the surrounding app. Losing focus
auto-closes the dropdown.

Use C<RadioGroup> instead when you want the options always visible;
use C<Select> when you want compact real estate.

=head1 EXAMPLES

=head2 Inside a form

=begin code :lang<raku>

my $theme-select = Selkie::Widget::Select.new(
    sizing => Sizing.fixed(1),
);
$theme-select.set-items(<Auto Light Dark>);

$app.store.subscribe-with-callback(
    'sync-theme-select',
    -> $s { ($s.get-in('settings', 'theme') // 0).Int },
    -> Int $v { $theme-select.select-index($v) },
    $theme-select,
);
$theme-select.on-change.tap: -> $v {
    $app.store.dispatch('settings/set', field => 'theme', value => $v);
};

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::RadioGroup> — always-visible equivalent
=item L<Selkie::Widget::ListView> — full-height scrollable list

=end pod

use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

use Selkie::Widget;
use Selkie::Style;
use Selkie::Event;

unit class Selkie::Widget::Select does Selkie::Widget;

has @!items;
has UInt $!selected = 0;
has UInt $!cursor = 0;
has UInt $!scroll-offset = 0;
has Str $.placeholder is rw = '';
has UInt $.max-visible = 8;
has Bool $!open = False;
has Bool $!focused = False;
has NcplaneHandle $!dropdown-plane;
has Supplier $!change-supplier = Supplier.new;

method new(*%args --> Selkie::Widget::Select) {
    %args<focusable> //= True;
    callwith(|%args);
}

method items(--> List) { @!items.List }
method selected(--> UInt) { $!selected }
method selected-value(--> Str) { @!items[$!selected] // Str }
method is-open(--> Bool) { $!open }

method on-change(--> Supply) { $!change-supplier.Supply }

method set-items(@new-items) {
    # Preserve the currently-selected value by label if it's still present.
    # Otherwise clamp to bounds.
    my Str $prev = @!items ?? (@!items[$!selected] // Str) !! Str;

    @!items = @new-items;
    $!scroll-offset = 0;
    self!close-dropdown;

    if @!items.elems == 0 {
        $!selected = 0;
        $!cursor = 0;
    } else {
        my $found = $prev.defined ?? @!items.first($prev, :k) !! Nil;
        $!selected = $found // ($!selected min (@!items.elems - 1));
        $!cursor = $!selected;
    }

    self.mark-dirty;
}

method select-index(UInt $idx) {
    return unless @!items;
    my UInt $clamped = $idx min (@!items.elems - 1);
    return if $clamped == $!selected;
    $!selected = $clamped;
    $!change-supplier.emit($!selected);
    self.mark-dirty;
}

method set-focused(Bool $f) {
    $!focused = $f;
    self!close-dropdown unless $f;
    self.mark-dirty;
}

method is-focused(--> Bool) { $!focused }

method open() {
    return unless @!items;
    return if $!open;
    $!open = True;
    $!cursor = $!selected;
    $!scroll-offset = 0;
    self!ensure-cursor-visible;
    self.mark-dirty;
}

method close() {
    self!close-dropdown;
}

method !close-dropdown() {
    return unless $!open;
    $!open = False;
    if $!dropdown-plane {
        ncplane_destroy($!dropdown-plane);
        $!dropdown-plane = NcplaneHandle;
    }
    self.mark-dirty;
}

method !dropdown-height(--> UInt) {
    @!items.elems min $!max-visible;
}

method !ensure-cursor-visible() {
    my UInt $vh = self!dropdown-height;
    if $!cursor < $!scroll-offset {
        $!scroll-offset = $!cursor;
    } elsif $!cursor >= $!scroll-offset + $vh {
        $!scroll-offset = $!cursor - $vh + 1;
    }
}

method !max-offset(--> UInt) {
    my UInt $vh = self!dropdown-height;
    @!items.elems > $vh ?? @!items.elems - $vh !! 0;
}

method render() {
    return without self.plane;
    ncplane_erase(self.plane);

    my UInt $w = self.cols;

    # Render the closed display (always visible)
    my $display = @!items ?? @!items[$!selected] // $!placeholder !! $!placeholder;
    my $arrow = $!open ?? '▲' !! '▼';
    my $label = "$arrow $display";
    $label = $label.substr(0, $w) if $label.chars > $w;
    $label = $label ~ (' ' x (($w - $label.chars) max 0));

    if $!focused {
        ncplane_set_fg_rgb(self.plane, 0xFFFFFF);
        ncplane_set_bg_rgb(self.plane, 0x4A4A8A);
        ncplane_set_styles(self.plane, NCSTYLE_BOLD);
    } else {
        my $style = self.theme.input;
        self.apply-style($style);
    }
    ncplane_putstr_yx(self.plane, 0, 0, $label);

    # Render dropdown if open
    self!render-dropdown if $!open;

    self.clear-dirty;
}

method !render-dropdown() {
    return without self.plane;
    return unless @!items;

    my UInt $dh = self!dropdown-height;
    my UInt $dw = self.cols;

    # Create or resize dropdown plane (child of our plane, positioned below)
    if $!dropdown-plane {
        ncplane_move_yx($!dropdown-plane, 1, 0);
        ncplane_resize_simple($!dropdown-plane, $dh, $dw);
    } else {
        my $opts = NcplaneOptions.new(y => 1, x => 0, rows => $dh, cols => $dw);
        $!dropdown-plane = ncplane_create(self.plane, $opts);
    }
    return without $!dropdown-plane;

    ncplane_erase($!dropdown-plane);

    # Ensure scroll bounds
    my UInt $max = self!max-offset;
    $!scroll-offset = $max if $!scroll-offset > $max;

    my $normal = self.theme.text;
    my $highlight = self.theme.text-highlight;
    my $base = self.theme.base;

    for ^$dh -> $row {
        my UInt $idx = $!scroll-offset + $row;
        last if $idx >= @!items.elems;

        my Bool $is-cursor = $idx == $!cursor;
        my Bool $is-selected = $idx == $!selected;

        my $marker = $is-selected ?? '●' !! ' ';
        my $text = "$marker @!items[$idx]";
        $text = $text.substr(0, $dw) if $text.chars > $dw;
        $text = $text ~ (' ' x (($dw - $text.chars) max 0));

        if $is-cursor {
            ncplane_set_fg_rgb($!dropdown-plane, $highlight.fg) if $highlight.fg.defined;
            ncplane_set_bg_rgb($!dropdown-plane, 0x3A3A5A);
            ncplane_set_styles($!dropdown-plane, $highlight.styles);
        } else {
            ncplane_set_fg_rgb($!dropdown-plane, $normal.fg) if $normal.fg.defined;
            ncplane_set_bg_rgb($!dropdown-plane, 0x2A2A3E);
            ncplane_set_styles($!dropdown-plane, 0);
        }

        ncplane_putstr_yx($!dropdown-plane, $row, 0, $text);
    }
}

method handle-event(Selkie::Event $ev --> Bool) {
    return False unless $!focused;

    if $ev.event-type ~~ KeyEvent {
        if $!open {
            return self!handle-open-event($ev);
        } else {
            return self!handle-closed-event($ev);
        }
    }

    # Mouse scroll when open
    if $!open && $ev.event-type ~~ MouseEvent {
        given $ev.id {
            when NCKEY_SCROLL_UP {
                if $!cursor > 0 { $!cursor--; self!ensure-cursor-visible; self.mark-dirty }
                return True;
            }
            when NCKEY_SCROLL_DOWN {
                if $!cursor < @!items.elems - 1 { $!cursor++; self!ensure-cursor-visible; self.mark-dirty }
                return True;
            }
        }
    }

    self!check-keybinds($ev);
}

method !handle-closed-event(Selkie::Event $ev --> Bool) {
    given $ev.id {
        when NCKEY_ENTER | NCKEY_SPACE {
            self.open;
            return True;
        }
    }
    self!check-keybinds($ev);
}

method !handle-open-event(Selkie::Event $ev --> Bool) {
    given $ev.id {
        when NCKEY_UP {
            if $!cursor > 0 { $!cursor--; self!ensure-cursor-visible; self.mark-dirty }
            return True;
        }
        when NCKEY_DOWN {
            if $!cursor < @!items.elems - 1 { $!cursor++; self!ensure-cursor-visible; self.mark-dirty }
            return True;
        }
        when NCKEY_PGUP {
            my $jump = self!dropdown-height max 1;
            $!cursor = $!cursor >= $jump ?? $!cursor - $jump !! 0;
            self!ensure-cursor-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_PGDOWN {
            my $jump = self!dropdown-height max 1;
            $!cursor = ($!cursor + $jump) min (@!items.elems - 1);
            self!ensure-cursor-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_HOME {
            $!cursor = 0;
            self!ensure-cursor-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_END {
            $!cursor = @!items.elems - 1;
            self!ensure-cursor-visible;
            self.mark-dirty;
            return True;
        }
        when NCKEY_ENTER | NCKEY_SPACE {
            if $!cursor != $!selected {
                $!selected = $!cursor;
                $!change-supplier.emit($!selected);
            }
            self!close-dropdown;
            return True;
        }
        when NCKEY_ESC {
            self!close-dropdown;
            return True;
        }
    }
    # When open, consume all key events to act as focus trap
    return True;
}

method destroy() {
    if $!dropdown-plane {
        ncplane_destroy($!dropdown-plane);
        $!dropdown-plane = NcplaneHandle;
    }
    self!destroy-plane;
}
