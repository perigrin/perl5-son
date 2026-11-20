---
name: chalk-takes-the-class-read-wire
description: "chalk branch chalk-arms (2026-11-20) at producer cc9d970: RefType::memory_operand, class reads made before a bless, W4 deleted, the hash rule narrowed to a list assignment's count; census 426, probes WRONG 0. What the producer still owes"
metadata:
  type: project
---

Chalk side of [[a-class-read-names-its-memory-version]], on chalk branch
`chalk-arms` (off bson/llvm-corpus 507c6875), four commits after 39b15261.

**What chalk did:**

- `Chalk::IR::Node::RefType::memory_operand` (second input where there is
  one). That alone puts adjacency-08_references, -10_io, -11_oo back: census
  426 / DIFFERS 0 / LLI_FAIL 0.
- A bless is a store to the class: before the walk makes a pinned bless it
  makes every class read (`reads_class`: RefType, builtin kind `class_name`)
  still waiting at a passed version (`class_reads_settled`, which is
  `hash_reads_settled` + `reads_before` with a filter). A sub call already did
  this for every read. WireCheck's `_class_reads_across_a_bless` is deleted.
- `Count` of a package hash's bare `EntryDef` is a key count
  (Containers.pm, the same `is_package_aggregate && sigil eq '%'` test
  `hash_of` uses). hs7, hs9 SAME.
- `_hashes_read_as_scalars` is gone; what is left is
  `_hash_assigns_read_as_scalars` (below).
- substr outside its string is undef (fl10 SAME); stopped at run time only
  where perl's warnings may be on (perl warns, chalk raises none) and for the
  four-argument substr, which dies.

**Lessons:**

- **The old rule plus the new wire was WRONG for a neighbour of st16.** At
  chalk 39b15261 with cc9d970, `my @o = ({}, {}); for my $i (0 .. 1) { my $r =
  ref($o[$i]); bless $o[$i], "K$i"; print $r, " ", ref($o[$i]), "\n" }`
  printed `K0 K0` for `HASH K0`: W4 passed it ("the read names the bless") and
  nothing made the first read before the bless. No probe has it. A rule
  narrowed because the wire got better must be run with the consumer change
  that the better wire needs, not ahead of it.
- **A list assignment to a hash, as a scalar, is still the hash's list on
  the wire.** `while (my %i = f())`, `if (my %h = f())`, `my $n = (%h = f())`,
  `(%g = f()) ? "t" : "f"`: the HashLiteral (`sigil %`, a symbol) feeds the
  If / Not / TernaryExpr / VarDecl directly. perl's value is the count of
  the RIGHT side (`(a => 1, a => 2)` is 4, the hash holds 1). With chalk's
  rule off, `our %g; sub f { () } (%g = f()) ? "t" : "f"` printed `t`. So the
  rule is narrowed to HashLiteral operands, not deleted. The producer fix is a
  Count of the right side's list (not of the hash) at that position.
- **A read through a reference under a class read is refused across a
  bless unless it is the statement before it** (`my $r = ref($o->{a}); print
  "x"; bless $o->{a}, "K"` -> "a read through a reference waiting across a
  bless"): the element read may die, so it is not made early. Loud.
- **`reftype` (Scalar::Util) is not lowered by chalk at all** ("Call builtin
  reftype", probe cr3): a gap, not this change.
- **Run chalk's probe tool with PERL5_SON_LIB set.** Without it the harness
  takes `$HOME/dev/perl5-son/lib`, an older producer, and every hash-truth
  probe read WRONG (`HASH(0x...)` for a count). Five WRONG rows that were the
  environment, not the code.

- **A new versioned read is a new node to every recorded oracle.** chalk's
  `t1-integer-intervals-prove-nothing-new.t` holds T1's answers node by node;
  `Count(@ARGV, MemStart)` (a package array read as a scalar) was three rows
  it had never seen, and "proven something the oracle did not" failed. The
  rows were added by hand (a count is an IV); a re-record would also have
  dropped the nine recorded lost proofs.

**Measured at chalk 8c512c2e, producer cc9d970:** census ROUNDTRIP 426,
DIFFERS 0, LLI_FAIL 0, GAP 5; probes SAME 348, REFUSED 114, LOUD 2 (ar17,
im23: autovivification), WRONG 0; corpus gate 222; suite 917 files, 0
failing.

**Still open on the producer side:** [[a-bless-only-arm-loses-its-if]].
