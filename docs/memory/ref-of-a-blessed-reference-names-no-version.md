---
name: ref-of-a-blessed-reference-names-no-version
description: "bless1 and st16 cannot be restored on chalk's side: RefType floats with no memory input, so `bless $h; print ref($h)` and `my $r = ref($h); bless $h; print $r` are one wire. The producer must version or pin the read"
metadata:
  type: project
---

Chalk step 2c (2026-11-20), at producer 72ada53 and at placement-pins 9d66925.

**The two programs, one wire** (canonical JSON, `diff` says identical):

    my $h = {}; bless $h, "K"; print ref($h), "\n";                 # K     (probe bless1)
    my $h = {}; my $r = ref($h); bless $h, "K"; print $r, "\n";     # HASH

Both are `RefType(HashLiteral)` floating, `Call bless` pinned after the
literal, `Print(RefType)` pinned after the bless. The `my $r` VarDecl is not
on the chain and nothing reads it. T2 makes a floating node at its first
pinned use, so it prints K for both.

**So chalk's W4 rule (`_class_reads_across_a_bless`) stays**, and bless1 and
st16 -- SAME at chalk 6cbaaee5 by the luck of where the read happened to
stand -- stay REFUSED. With the rule off the probes ef9, st2, vp19, st14,
ex1, ex4 print wrong answers. st16 is the same shape in a loop: its second
`RefType(Subscript(@o, $i, mem-after-push))` names the memory version before
the bless, and is first used after it.

**What would restore them, in B::SoN:** bless is a store to the referent's
class. Either RefType / `blessed` take a memory input that the bless's
memory output feeds (as a package scalar's read does since step 2b), or the
read is pinned where it stands when the program blesses anything that is
not fresh. Then chalk deletes W4 and
`t2-bless-a-scalar-or-code-reference.t`'s third case goes back to perl's
answer.

**How to check a "can chalk tell these apart" question:** dump both wires
through `JSON::PP->new->canonical->pretty` and diff. Identical means no
consumer rule can be narrowed; do not try.

The same holds for a hash as a condition (`%h ? :`): HashLiteral feeds the
TernaryExpr at no memory version; chalk's `_hashes_read_as_scalars` stays,
and `llvm-an-array-as-a-condition-is-its-count.t` keeps its refused case.
