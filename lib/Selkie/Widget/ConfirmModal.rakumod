use Selkie::Widget::Modal;
use Selkie::Widget::Text;
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

    # Message
    $content.add: Selkie::Widget::Text.new(
        text   => $message,
        sizing => Sizing.flex,
        style  => Selkie::Style.new(fg => 0xC0C0C0),
    );

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
