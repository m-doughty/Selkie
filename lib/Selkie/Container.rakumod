unit role Selkie::Container;

use Selkie::Widget;
use Selkie::Event;

also does Selkie::Widget;

has @!children;

method children(--> List) { @!children.List }

method add(Selkie::Widget $child --> Selkie::Widget) {
    $child.parent = self;
    # Propagate store down to child (and its subtree)
    self!propagate-store($child) if self.store;
    @!children.push($child);
    self.mark-dirty;
    $child;
}

method !propagate-store(Selkie::Widget $widget) {
    $widget.set-store(self.store);
    # Propagate to Container children
    if $widget ~~ Selkie::Container {
        for $widget.children -> $child {
            self!propagate-store($child);
        }
    }
    # Propagate to Border/Modal content (stored separately from @children)
    if $widget.can('content') && $widget.content.defined {
        self!propagate-store($widget.content);
    }
}

method remove(Selkie::Widget $child) {
    self!unsubscribe-tree($child);
    $child.destroy;
    @!children = @!children.grep(* !=== $child);
    self.mark-dirty;
}

method clear() {
    self!unsubscribe-tree($_) for @!children;
    .destroy for @!children;
    @!children = ();
    self.mark-dirty;
}

method !unsubscribe-tree(Selkie::Widget $widget) {
    $widget.store.unsubscribe-widget($widget) if $widget.store;
    if $widget ~~ Selkie::Container {
        for $widget.children -> $child {
            self!unsubscribe-tree($child);
        }
    }
}

method !render-children() {
    my $cascade = self.is-dirty;
    for @!children -> $child {
        # If this container is dirty, cascade dirty to children so the
        # entire subtree re-renders (e.g. images re-blit after modal close)
        $child.mark-dirty if $cascade && !$child.is-dirty;
        $child.render if $child.is-dirty;
    }
}

method focusable-descendants(--> Seq) {
    gather {
        for @!children -> $child {
            take $child if $child.focusable;
            if $child ~~ Selkie::Container {
                .take for $child.focusable-descendants;
            }
        }
    }
}

method destroy() {
    .destroy for @!children;
    @!children = ();
    self!destroy-plane;
}
