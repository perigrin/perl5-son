---
name: a-list-is-not-a-reference-or-an-array
description: Perl treats a list value differently from an array and from a ref; three Deparse renderings got this wrong
metadata:
  type: project
---

A `List`-stamped node is **not** an array and **not** a reference, and
SoN::Deparse got that wrong three separate ways. Each was silent.

| operation | wrong | right | why |
|---|---|---|---|
| count | `scalar(() = LIST)` | `do { my @c = LIST; scalar(@c) }` | assigning to an EMPTY list tells `split` zero fields are wanted, and it obliges — the count comes back 1 |
| index | `LIST->[i]` | `(LIST)[i]` | the arrow dereferences; a list has nothing to dereference and it dies |
| scalar ctx | `scalar(LIST)` | — | that is the COMMA OPERATOR: `scalar((5,2,9))` is 9, the last element |

**`split` is the sharp case** because it sizes itself to its target:

    scalar(() = split(/,/,"a,b,c"))                 1
    scalar(() = split(/,/,"a,b,c", -1))             3
    do { my @t = split(/,/,"a,b,c"); scalar(@t) }   3
    scalar(() = (1,2,3))                            3   right, by luck

So the old idiom was correct for an ordinary list and wrong only for
split — which is exactly how it survived.

**How it was found:** a deparsed `comp/retainedlines.t` had been running
at 99.6% CPU for 28 HOURS. Its loop bound was a split count stuck at 1,
and its body indexed a split with an arrow. Neither showed up in the
suite; only a stray process did.

Related: [[read-generated-output-not-tests]].
