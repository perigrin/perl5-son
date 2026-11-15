---
name: A reference to an element reads memory
description: 2026-11-15 -- `\$a[i]` took no memory, so a shift before and after it were one graph, and a store through it went unseen by `"@a"`; now Ref [location, memory], pinned (perigrin approved)
type: feedback
---
Perl's array holds pointers to separate scalars: which scalar is at which
index is the array's layout (shift, push, splice, `$#a =` change it), what it
holds is its contents. `\$a[i]` is the scalar at index i NOW. B::SoN built the
Ref over a location Subscript (an address, no memory), so

    my $r = \$a[0]; shift @a      and      shift @a; my $r = \$a[0]

were one graph, and `my $r = \$a[0]; $$r = 5; print "@a"` flattened @a's
literal (`1 2` for `5 2`).

**Fix:** Ref takes `[location, memory]` (_op_takes_an_element: srefgen over
an aelem/helem, refgen of `\(@a)` or of elements), pinned where it stands via
_pin_tied_read and the memory version after it -- in %PINNED_MAY_DIE, so the
walks that look for "which store is this memory" step through it. Taking one
marks a `my` array mutated (walk: mutated_aggregate; pre-pass:
_mutated_aggregate_slots `||= 1`, not 'ref': a whole assign gives new
elements, which the reference does not see, as in perl).

**How to apply:** the deparser drops the memory input when rendering a Ref,
steps through a pinned Ref as through a pinned read, and keeps an unread one
as a statement (`\$h{x};` makes the key). A dead `\$a[-5]` is no longer a
"dead value that may die": it stands on the chain. A slice's references
(`\(@a[0,1])`) were one Ref over the Slice -- refused now.
