=begin pod

=head1 NAME

Selkie::Widget::ConfirmModal - Pre-built yes/no confirmation dialog

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget::ConfirmModal;

my $cm = Selkie::Widget::ConfirmModal.new;
$cm.build(
    title     => 'Delete file?',
    message   => "Really delete 'report.pdf'?",
    yes-label => 'Delete',
    no-label  => 'Cancel',
);

$cm.on-result.tap: -> Bool $confirmed {
    $app.close-modal;
    do-delete() if $confirmed;
};

$app.show-modal($cm.modal);
$app.focus($cm.no-button);     # safe default

=end code

=head1 DESCRIPTION

A wrapper around L<Selkie::Widget::Modal> with a pre-built title +
message + yes/no button row. Emits a C<Bool> on C<on-result> when the
user picks a button or presses Esc (Esc = False = No).

Use C<$cm.no-button> (or C<yes-button>) when calling C<focus> on the
app so the default focus is on the safer button.

Build the modal with C<build(...)> and pass the returned Modal to
C<$app.show-modal>. The C<.modal> accessor returns the same Modal
after construction.

A primary mouse click on either button activates it — Selkie::App's
coordinate dispatcher routes the click to the deepest hit (the Button
widget itself), and Button's built-in click handler fires the same
C<on-press> path Enter / Space drive. The default
C<dismiss-on-click-outside> stays False (a Yes/No decision shouldn't
be silently abandoned by a stray click).

=head1 EXAMPLES

=head2 Delete confirmation

=begin code :lang<raku>

sub confirm-delete($item) {
    my $cm = Selkie::Widget::ConfirmModal.new;
    $cm.build(
        title     => 'Delete',
        message   => "Delete '{$item.name}'?",
        yes-label => 'Delete',
        no-label  => 'Cancel',
    );
    $cm.on-result.tap: -> Bool $confirmed {
        $app.close-modal;
        if $confirmed {
            $app.store.dispatch('item/delete', id => $item.id);
            $app.toast('Deleted');
        }
    };
    $app.show-modal($cm.modal);
    $app.focus($cm.no-button);
}

=end code

=head1 SEE ALSO

=item L<Selkie::Widget::Modal> — underlying dialog
=item L<Selkie::Widget::FileBrowser> — similar wrapper pattern for file picking

=end pod

use Selkie::Widget::Modal;
use Selkie::Widget::Text;
use Selkie::Widget::RichText;
use Selkie::Widget::RichText::Span;
use Selkie::Widget::Button;
use Selkie::Layout::VBox;
use Selkie::Layout::HBox;
use Selkie::Sizing;
use Selkie::Style;

unit class Selkie::Widget::ConfirmModal;

has Selkie::Widget::Modal $.modal;
has Selkie::Widget::Button $!yes-btn;
has Selkie::Widget::Button $!no-btn;
has Supplier $!result-supplier = Supplier.new;

method on-result(--> Supply) { $!result-supplier.Supply }

method build(
    Str :$title = 'Confirm',
    Str :$message = 'Are you sure?',
    Str :$yes-label = 'Yes',
    Str :$no-label = 'No',
    Rat :$width-ratio = 0.4,
    Rat :$height-ratio = 0.3,
    --> Selkie::Widget::Modal
) {
    $!modal = Selkie::Widget::Modal.new(:$width-ratio, :$height-ratio);

    my $content = Selkie::Layout::VBox.new(sizing => Sizing.flex);

    # Title
    $content.add: Selkie::Widget::Text.new(
        text   => $title,
        sizing => Sizing.fixed(1),
        style  => Selkie::Style.new(fg => 0x7AA2F7, bold => True),
    );

    # Spacer
    $content.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(1));

    # Message — RichText so long prompts wrap to the modal's width
    # rather than clipping. Single span with the dim-grey message style.
    my $message-widget = Selkie::Widget::RichText.new(sizing => Sizing.flex);
    $message-widget.set-content([
        Selkie::Widget::RichText::Span.new(
            text  => $message,
            style => Selkie::Style.new(fg => 0xC0C0C0),
        ),
    ]);
    $content.add($message-widget);

    # Button row
    my $buttons = Selkie::Layout::HBox.new(sizing => Sizing.fixed(1));
    $content.add($buttons);

    # Left spacer
    $buttons.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    $!yes-btn = Selkie::Widget::Button.new(
        label  => $yes-label,
        sizing => Sizing.fixed(10),
    );
    $buttons.add($!yes-btn);

    # Gap between buttons
    $buttons.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.fixed(2));

    $!no-btn = Selkie::Widget::Button.new(
        label  => $no-label,
        sizing => Sizing.fixed(10),
    );
    $buttons.add($!no-btn);

    # Right spacer
    $buttons.add: Selkie::Widget::Text.new(text => '', sizing => Sizing.flex);

    $!modal.set-content($content);

    # Wire buttons
    $!yes-btn.on-press.tap: -> $ { $!result-supplier.emit(True) };
    $!no-btn.on-press.tap: -> $ { $!result-supplier.emit(False) };

    # Escape = No
    $!modal.on-key: 'esc', -> $ { $!result-supplier.emit(False) };

    $!modal;
}

method yes-button(--> Selkie::Widget::Button) { $!yes-btn }
method no-button(--> Selkie::Widget::Button) { $!no-btn }
