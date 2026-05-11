=begin pod

=head1 NAME

Selkie::Widget::FocusableByDefault - Mix-in role that defaults
C<focusable> to True at construction

=head1 SYNOPSIS

=begin code :lang<raku>

use Selkie::Widget;
use Selkie::Widget::FocusableByDefault;

unit class My::Toggle does Selkie::Widget does Selkie::Widget::FocusableByDefault;

# No `method new` override needed — composing the role causes
# `My::Toggle.new(...)` to default `focusable => True` unless the
# caller passes it explicitly.

=end code

=head1 DESCRIPTION

Most input widgets in Selkie are focusable by default — Buttons,
Checkboxes, TextInputs, ListViews, RadioGroups, and so on. Before this
role existed, each of those widgets carried the same three-line C<new>
override:

=begin code :lang<raku>

method new(*%args --> ::?CLASS) {
    %args<focusable> //= True;
    callwith(|%args);
}

=end code

That boilerplate is what this role consolidates. Compose it on any
widget that should default to focusable, and the role's C<new> takes
care of the C<focusable> default — callers that pass an explicit
C<:!focusable> or C<:focusable(False)> still win, because C<//=>
respects the caller's choice.

=head2 Why a role and not a base class?

Selkie's widget hierarchy is role-based (everything composes
C<Selkie::Widget>) rather than class-based, so a role mixin is the
natural shape. Composing this role doesn't add any state — only the
C<new> behaviour — so it's free of the usual diamond-inheritance
hazards that come with multi-class hierarchies.

=head2 What if my widget needs more constructor logic?

Implement C<submethod TWEAK> on your class — it runs after C<new> has
returned the new object, with all attributes initialized. The role's
C<new> doesn't interfere with C<TWEAK>; both compose cleanly.

=end pod

unit role Selkie::Widget::FocusableByDefault;

#| Constructor wrapper. Defaults C<focusable> to True before delegating
#| to the next C<new> candidate in MRO (typically C<Mu.new>). An
#| explicit C<:focusable(False)> from the caller is preserved.
method new(*%args --> ::?CLASS) {
    %args<focusable> //= True;
    callwith(|%args);
}
