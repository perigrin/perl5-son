---
name: a-list-assign-counts-its-right-side
description: "Wire v2 stage 1b: a list assignment in scalar context is a Count of the list assigned (`_list_count`), taken before the store; a hash target used to push the hash itself. `() = LIST` shared two wrong answers: a reference counted as its referent, a hash as its keys"
metadata:
  type: project
---

Branch `v2-s01`, 2026-11-20. The debt named in
[[chalk-takes-the-class-read-wire]]: `while (my %i = f())`, `if (%h = f())`,
`my $n = (%h = f())`, `(%g = f()) ? :` handed the HashLiteral to the If, the
Not, the TernaryExpr or the Coerce.

**What changed.** `_list_count($factory, $sim, @values)` in
`SoN::FromOptree` builds the count of a list: 1 per scalar (folded into one
Constant), `Count` per array or list-valued value, twice the `Count` of a
hash, and `Count [ArrayLiteral [call]]` for a sub call or a list-context
match. The aassign handler computes it for a hash target in scalar context
right after it pops the right side, and pushes it at all three places that
pushed the hash (the bound value, the tied / referenced container, the
literal). `() = LIST` uses the same sub.

**Lessons:**

- **Count before the store.** Each `Count` takes the sim's memory when it is
  made. `%g = (%g, b => 2)` must count the %g it read; made after
  `_entry_store`, the Count would read the hash just written.
- **`_is_aggregate_node` is not "yields N elements".** It answers true for
  ArrayRef and HashRef stamps (a reference is one element) and for a hash
  (which flattens to twice its Count). `my $n = () = ($r, $r)` was 6 for
  perl's 2 and `() = %h` was 2 for 4, both silently, both older than this
  work. A predicate written for "is this a container to subscript" was reused
  for "how many values does this give a list".
- **A dead allocation is a deparser GAP** ("an anonymous ArrayLiteral
  reached as a statement"): `my $r = [1,2,3];` with `$r` never read. The fix
  made `() = ($r, $r)` a constant 2 and the test's `$r` unread; the test
  reads it now. Loud, not fixed here.
- **chalk lowers the count but not a hash made of a call's list.** With the
  shape gone, `(%g = f())` is refused by T2 for "a call used both as a list
  and as a scalar" (the call feeds the HashLiteral and the counted list),
  and plain `my %h = f()` for "a {...} of an odd list". From an array or a
  literal list every form is perl's answer. chalk's WireCheck rule
  `_hash_assigns_read_as_scalars` is deleted.
- **A refusal can outlive its reason.** "a hash assignment from a ternary
  counted in scalar context" was refused because the old shape spelled the
  pairs; a Count of the ternary (stamped Array) says it, and the three cases
  round-trip. A ternary whose stamp is Unknown is still refused, by a new
  name.

Related: [[a-class-read-names-its-memory-version]],
[[a-list-assign-is-placed-by-where-its-targets-live]].
