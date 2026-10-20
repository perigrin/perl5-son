---
name: opf-mod-is-not-a-write
description: OPf_MOD means POTENTIAL lvalue; perl leaves it on comparison operands after folding a dead branch arm
metadata:
  type: reference
---

`OPf_MOD` (0x20) on an optree op means POTENTIAL lvalue, not an actual write.
perl leaves it set on a **comparison's first operand** after folding a dead
branch arm: `if (0) {...} elsif ($x != $y)` compiles that `$x` as `padsv sM`
even though nothing ever stores through it.

Two places in FromOptree.pm read that flag as "assignment target", and both were
wrong for comparisons (fixed in 338b403):

- compound-assignment detection (the `OP=` family). Comparisons have no member
  in that family -- `!==`, `===`, `<==`, `>==` are all syntax errors -- so a
  comparison is never a read-modify-write however OPf_MOD is set.
- the `padsv` handler, which pushed a fresh unbound PadAccess instead of the
  slot's live binding.

**Checking the consuming op requires scanning past sibling operand pushes.**
`$x != $y` runs `padsv, padsv, ne`, so `$op->next` from the first operand is the
SECOND operand, not the comparison.

Debugging note: the way in was tracing `StackSim::define` back to the rebinding
site. Three hypotheses were measured and disproved first -- a stack slip (depths
matched), a double walk from the scout (separate factories, scout nodes are
discarded), and an lvalue clobber (that code correctly guards on `$existing`).

Related: [[graph-correctness-needs-the-optree-not-the-source]]

## The third occurrence: sprintf and printf

perl also sets OPf_MOD on a plain pad READ passed to `sprintf` or `printf`,
neither of which writes it. Measured:

    sprintf("%d",$i)   padsv sM      printf("%d",$i)  padsv sM
    join(",",$i)       padsv s       push(@a,$i)      padsv s
    print($i)          padsv s       substr($i,0,1)   padsv s
    chomp($i)          padsv sRM     <- a GENUINE writer

So OPf_REF accompanies a real in-place write, but keying on that would just
swap one incidental bit for another. **What CONSUMES the value decides**, and
the `padsv` handler's forward scan already asks that question for the
comparison case -- `%READS_ITS_OPERANDS` extends it to sprintf/prtf.

Symptom when wrong: `my $i = 3; printf "n=%d\n", $i` emitted a program
reading an undeclared `$i` and printed `n=0`. Only visible when the argument
resists constant folding; `print "$i"` folds to a literal and never shows it.
