#!/usr/bin/env raku
#
# chat.raku — A retro echo-bot with rich-text rendering.
#
# Demonstrates:
#   - CardList of variable-height cards (chat messages)
#   - RichText with multiple Span styles (per-speaker coloring)
#   - MultiLineInput for composing
#   - Border with auto-focus highlighting via the store
#   - Toast for transient feedback
#   - Theme override at runtime (Ctrl+T toggles light/dark)
#   - The full pattern: messages live in the store; a callback subscription
#     rebuilds the CardList whenever they change
#
# This is a local echo: the "bot" just transforms what you type. No backend.
#
# Run with:  raku -I lib examples/chat.raku

use Selkie::App;
use Selkie::Layout::VBox;
use Selkie::Widget::Text;
use Selkie::Widget::MultiLineInput;
use Selkie::Widget::CardList;
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Widget::Border;
use Selkie::Sizing;
use Selkie::Style;
use Selkie::Theme;

# --- Themes ----------------------------------------------------------------

sub dark-theme(--> Selkie::Theme) {
    Selkie::Theme.new(
        base              => Selkie::Style.new(fg => 0xEEEEEE, bg => 0x16162E),
        text              => Selkie::Style.new(fg => 0xEEEEEE),
        text-dim          => Selkie::Style.new(fg => 0x888899),
        text-highlight    => Selkie::Style.new(fg => 0xFFFFFF, bold => True),
        border            => Selkie::Style.new(fg => 0x444466),
        border-focused    => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
        input             => Selkie::Style.new(fg => 0xEEEEEE, bg => 0x1A1A2E),
        input-focused     => Selkie::Style.new(fg => 0xFFFFFF, bg => 0x2A2A3E),
        input-placeholder => Selkie::Style.new(fg => 0x606080, italic => True),
        scrollbar-track   => Selkie::Style.new(fg => 0x333344),
        scrollbar-thumb   => Selkie::Style.new(fg => 0x7AA2F7),
        divider           => Selkie::Style.new(fg => 0x444466),
    );
}

sub light-theme(--> Selkie::Theme) {
    Selkie::Theme.new(
        base              => Selkie::Style.new(fg => 0x222222, bg => 0xF5F5F0),
        text              => Selkie::Style.new(fg => 0x222222),
        text-dim          => Selkie::Style.new(fg => 0x666666),
        text-highlight    => Selkie::Style.new(fg => 0x000000, bold => True),
        border            => Selkie::Style.new(fg => 0xCCCCCC),
        border-focused    => Selkie::Style.new(fg => 0x3366CC, bold => True),
        input             => Selkie::Style.new(fg => 0x222222, bg => 0xFFFFFF),
        input-focused     => Selkie::Style.new(fg => 0x000000, bg => 0xEEEEFF),
        input-placeholder => Selkie::Style.new(fg => 0x999999, italic => True),
        scrollbar-track   => Selkie::Style.new(fg => 0xDDDDDD),
        scrollbar-thumb   => Selkie::Style.new(fg => 0x3366CC),
        divider           => Selkie::Style.new(fg => 0xCCCCCC),
    );
}

my $app = Selkie::App.new(theme => dark-theme());

# --- Store handlers -------------------------------------------------------
#
# Each message is { speaker => Str, text => Str }.

$app.store.register-handler('app/init', -> $st, %ev {
    (db => {
        messages => [
            { speaker => 'bot', text => 'Hello! Type something and I will echo it back, transformed.' },
        ],
        dark => True,
    },);
});

$app.store.register-handler('chat/send', -> $st, %ev {
    my $text = (%ev<text> // '').trim;
    if $text.chars == 0 {
        ();
    } else {
        my @msgs = ($st.get-in('messages') // []).Array;
        @msgs.push({ speaker => 'you', :$text });
        # Synthesize a "bot" reply by reversing the input
        my $reply = $text.flip;
        @msgs.push({ speaker => 'bot', text => "Reversed: $reply" });
        (db => { messages => @msgs },);
    }
});

$app.store.register-handler('chat/clear', -> $st, %ev {
    (db => { messages => [] },);
});

$app.store.register-handler('theme/toggle', -> $st, %ev {
    (db => { dark => !($st.get-in('dark') // True) },);
});

# --- Widget tree ----------------------------------------------------------

my $root = Selkie::Layout::VBox.new(sizing => Sizing.flex);
$app.add-screen('main', $root);
$app.switch-screen('main');

$root.add: Selkie::Widget::Text.new(
    text   => '  Echo Chat  —  Ctrl+Enter send, Ctrl+L clear, Ctrl+T theme, Ctrl+Q quit',
    sizing => Sizing.fixed(1),
    style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
);

# Message list (CardList in a Border so focus is visible)
my $cards = Selkie::Widget::CardList.new(sizing => Sizing.flex);
my $cards-border = Selkie::Widget::Border.new(title => 'Chat', sizing => Sizing.flex);
$cards-border.set-content($cards);
$root.add($cards-border);

# Input
my $input = Selkie::Widget::MultiLineInput.new(
    sizing      => Sizing.fixed(1),
    max-lines   => 5,
    placeholder => 'Type a message — Ctrl+Enter to send',
);
my $input-border = Selkie::Widget::Border.new(title => 'Compose', sizing => Sizing.fixed(3));
$input-border.set-content($input);
$root.add($input-border);

# --- Wiring ---------------------------------------------------------------

$input.on-submit.tap: -> $text {
    if $text.chars > 0 {
        $app.store.dispatch('chat/send', :$text);
        $input.clear;
    }
};

# --- Subscriptions --------------------------------------------------------

# Build a styled card per message and rebuild the CardList when messages
# change. For brevity we destroy and recreate cards on every change — fine
# at chat-app scale. A higher-volume app would diff and patch.
$app.store.subscribe-with-callback(
    'message-cards',
    -> $s { $s.get-in('messages') // [] },
    -> @msgs {
        $cards.clear-items;
        for @msgs -> %m {
            my $is-bot = %m<speaker> eq 'bot';
            my $name-style = $is-bot
                ?? Selkie::Style.new(fg => 0x9ECE6A, bold => True)
                !! Selkie::Style.new(fg => 0x7AA2F7, bold => True);
            my $body-style = Selkie::Style.new(fg => 0xEEEEEE);

            my $rich = Selkie::Widget::RichText.new(sizing => Sizing.flex);
            $rich.set-content([
                Selkie::Widget::RichText::Span.new(
                    text  => "{%m<speaker>}: ",
                    style => $name-style,
                ),
                Selkie::Widget::RichText::Span.new(
                    text  => %m<text>,
                    style => $body-style,
                ),
            ]);

            # Wrap in its own Border so cards visually separate.
            my $border = Selkie::Widget::Border.new(sizing => Sizing.flex);
            $border.set-content($rich);

            $cards.add-item(
                $rich,                      # positional: the inner widget
                root   => $border,          # the rendered root (the Border)
                height => 3,                # 1 text line + 2 border rows
                :$border,                   # the Border for focus highlighting
            );
        }
        $cards.select-last if @msgs;
    },
    $cards,
);

# Theme toggle: install the appropriate theme on the root each time `dark`
# changes. Children inherit by walking up the parent chain.
$app.store.subscribe-with-callback(
    'theme',
    -> $s { $s.get-in('dark') // True },
    -> Bool $dark {
        $root.set-theme($dark ?? dark-theme() !! light-theme());
    },
    $root,
);

# --- Global keybinds ------------------------------------------------------

$app.on-key('ctrl+q', -> $ { $app.quit });
$app.on-key('ctrl+l', -> $ {
    $app.store.dispatch('chat/clear');
    $app.toast('Cleared');
});
$app.on-key('ctrl+t', -> $ {
    $app.store.dispatch('theme/toggle');
    $app.toast('Theme toggled');
});

# --- Go -------------------------------------------------------------------

$app.store.dispatch('app/init');
$app.store.tick;

$app.focus($input);
$app.run;
