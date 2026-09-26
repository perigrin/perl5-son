# A destructive s/// or tr/// on a lexical

**Status:** FIXED. EMITS_INVALID_PERL 2 -> 0 (emissions perl refuses to
compile, not cases we failed to read); the s/// half turned a REFUSAL into a
round trip as well.

Renamed from `-a-destructive-tr-on-a-lexical`: the defect was never tr///'s.
s/// has it identically and merely refused where tr/// miscompiled.

## The defect

```perl
my $tr = "a.c";
my $cnt = ($tr =~ tr/./Z/);
print "$tr $cnt\n";      # perl: aZc 1
```

emitted `("a.c" =~ tr[.][Z])` -- `Can't modify constant item in
transliteration (tr///)`. Corpus cases 010 and 180.

**The identical s/// shape REFUSED rather than miscompiling**, which is why
only tr/// was visible:

```
GAP: a counted s/// whose subject is a `Constant` has no lvalue to modify --
the graph names a value, and no EntryWrite names the variable it was bound to
```

One defect, two failure modes. The package-scalar form of both was always
correct, because its subject is an EntryDef -- itself an lvalue.

## Why the subject was a value

A pad read resolves to the value the slot is bound to. For tr/// the op carries
the targ and pushes NO padsv operand at all --

```
7  <"> trans[$tr:1,3] sP/TRANS=ONLY_UTF8_INVARIANTS
```

-- so `pop_node` returns whatever the preceding assignment left behind. For
s/// `_subst_target` calls `$sim->lookup`, which returns the same Constant.

A pad has no `EntryWrite`, so `_subst_lvalue`'s name-recovery (which works for
package scalars) had nothing to walk back to.

## The fix: demote the slot

A destructive substitution MUTATES STORAGE, which is the property `\$x` has, so
it gets the same demotion. `_address_taken` now marks the targ of a `subst`
without PMf_NONDESTRUCT and of a `trans` (not `transr`).

Demoted, the slot's store is an ordinary `Assign(PadAccess, value)` on the
control chain, reads are memory-threaded PadAccess nodes that render as the
variable, and the declaration survives. Everything the lvalue needed, from a
mechanism that already existed and was already tested.

Four parts, and each was necessary:

1. **Demotion** (`_address_taken`) -- gives the slot a real store, so `my $s =
   "aaa"` is not pruned. Without it the emission compiled and read an
   UNDECLARED variable: a compile error traded for a silent wrong answer.
2. **The tr/// subject** -- `trans` reads the demoted slot rather than popping
   the stack. s/// gets this for free through `_subst_target`.
3. **The control pin** -- a destructive tr/// sets `control_in`, and so does
   the main-walker s/// site, which never had one (the loop-body site at
   FromOptree.pm:10045 always did: one operator, two declaration sites, and
   they had drifted).
4. **One run** (`_counted_lexical_subst`) -- a bound destructive form renders
   DESTRUCTIVELY, not `/r`, and a count reads a temporary instead of
   re-rendering.

## The two cases that caught partial fixes

**A read between the mutation and the count.**

```perl
my $t = "a.c"; my $c = ($t =~ tr/./Z/);
print "mid $t\n"; print "end $c\n";
```

perl prints `mid aZc / end 1`. Unpinned, the deparser emitted the tr/// where
its value was first READ -- the second print -- so the first printed `mid a.c`.
Silent. Every assertion on the single-statement shape passed; that shape cannot
see it.

**An UNCOUNTED destructive s///.** Requiring a count in
`_counted_lexical_subst` regressed five corpus cases from correct to silently
wrong: `$s =~ s/a/z/;` with nothing reading the count was bound and rendered
`/r`, substituting into a copy. The count decides whether a TEMPORARY is
needed, not whether the destructive form is.

## The pin is SCOPED, and an unscoped one regressed the package form

Pinning the main-walker s/// unconditionally broke three existing assertions in
`t/deparse-counted-subst-runs-once.t`. A package subject ALREADY has its
ordering, through the `EntryWrite` the destructive branch emits -- and that
write is what the deparser keys on to render the substitution once. Pinning as
well makes the node independently bindable, the generic path renders the
binding with `/r`, and the emission runs the substitution twice:

    our $s = "aaa"; my $n = ($s =~ s/a/b/g); print "$n $s"

    perl      3 bbb
    unscoped  $main::s = "aaa";
              my $eff6 = ("aaa" =~ s{a}{b}gr);
              $main::s = $eff6;
              print(($main::s =~ s{a}{b}g) . " " . $main::s)

-- the `/r` copy assigned back, then a second destructive run over the result.

So the pin goes exactly where the ordering is otherwise absent: `if
($target->isa('PadAccess'))`. THE TWO STORAGE CLASSES NEED DIFFERENT AMOUNTS OF
THE SAME FIX, which is the shape this whole document keeps arriving at -- a
package scalar was correct before any of this and a lexical needed four parts.

## A REFUSAL TEST BECAME FALSE, and that is the honest signal

`t/deparse-regex.t` asserted the refusal this fix removes:

    is $d->render($data), undef, 'a counted s/// over a folded subject refuses';
    like $d->gap, qr/no lvalue to modify/, '... naming what is missing';

with a comment explaining that "the graph names a Constant". It no longer does,
so the comment was provably false and the assertion had to go -- replaced with
the round trip it was standing in for, since the two things the refusal
protected (that the ORIGINAL changes, and that the count is the count) are only
visible by RUNNING the emission:

    my $s = "aaa"; my $n = ($s =~ s/a/b/g); print "$n $s\n";
      perl  3 bbb
      ours  3 bbb

This is [[removing-a-gap-can-create-a-miscompile]] from the safe side: the
producer stopped refusing, a consumer assertion went stale, and the SUITE said
so rather than the corpus. A refusal test that fails because the refusal was
fixed is the mechanism working -- the dangerous version is the one where no
test mentions the shape at all.

## Guards

`t/from-optree-destructive-tr-names-its-pad.t` -- the count form, the ordering
case, the s/// twin, the `/r` form (must keep a value subject), and the package
form (must keep its EntryDef).

Related: [[one-node-two-consumers-runs-twice]],
[[a-silent-drop-is-worse-than-a-refusal]],
[[one-operator-five-declaration-sites]]
