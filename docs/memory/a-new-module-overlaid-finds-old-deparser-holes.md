---
name: a-new-module-overlaid-finds-old-deparser-holes
description: Earley's first overlay dropped gate 3 from 488 to 374; every cause was a pre-existing defect the base also had, found by bisecting the overlay and confessing at the failing call
metadata:
  type: feedback
---

Overlaying chalk's Earley (first time it compiled) made 114 of chalk's test
files differ. None was Earley-specific; each was an old hole the new
module's shapes reached, and each reproduced at base:

- `while (my $n = shift @w)` with `$n` demoted: the store hung off the
  condition's shift, past the effects the header emits (`<><>`).
- `$a && (my $x = E)`: the arm's `my` had no binding before it, and both
  merges (value and real-control-flow) dropped it.
- `if/else` ending a sub, an arm storing an element then yielding a value.
- a read at the top of a pass of a variable stored later in it, spelled
  after the store (`=1;` for `x=1;`); the read was never bound because
  reads under loops are skipped (they froze conditions).
- an If whose arms both `last` met at a region feeding the exit; the walk
  ran through the exit and spelled the code after the loop in the body.
- an arm that runs a loop before its `next`: the edge search stopped at
  the inner loop's exit Region and never saw the latch.

**Why:** gate 3 is the only check that runs chalk's real call graphs, and a
newly overlaid module brings shapes no corpus case has.

**How to apply:** rebuild an overlay by hand (census `--emit`, copy into a
`git archive` tree), run one failing test there, restore one original
module to bisect, then patch the ORIGINAL module under test with
`Carp::confess` at the crash to name the emitted line. Minimize from that
line; the defect usually reproduces at base in a dozen lines.

Again with FilterComposite (60 DIFFERS): `$S/bisect.pl TEST` halves the
overlaid list automatically and named it in 8 runs. The hole was the
producer's, not the deparser's: `grep { blessed($_) }` read `$main::_`,
because a builtin's operand is OPf_MOD and only the padsv handler knew
`%READS_ITS_OPERANDS`. Run the full overlay comparison before calling a
batch done -- the unit suite and corpus were both green.
