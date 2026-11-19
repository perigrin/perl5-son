---
name: the-wire-is-checked-before-it-is-loaded
description: "chalk's WireCheck refuses floating effects and unversioned reads on the raw wire; three wrong probes have wires identical to right programs, so only the producer can fix them"
metadata: 
  node_type: memory
  type: project
  modified: 2026-11-19T00:00:00.000Z
---

Step 1 of the IR audit's plan (docs/research/son-ir-audit-2026-11-19) is done
in chalk, branch `refuse-floating` (off bson/llvm-corpus c1a48dfe, not
pushed). `Chalk::IR::Serialize::WireCheck` runs in `from_json` on the wire's
run set, before any graph is made, and dies `GAP: ...` by name. Probes:
WRONG 65 -> 3, REFUSED 95 -> 163, SAME 255 -> 249. Census unchanged.

**Why the raw wire:** the loader drops what control does not reach, so a
store B::SoN left floating is not in the loaded graph. A check there says
"ok". The check has to read the JSON nodes.

**Lessons:**

- **A refusal cannot be wider than the corpus allows.** The census sat at
  exactly 426, so every rule had to refuse zero right programs there. "Refuse
  every floating call" would have cost 012 and 055 (`$o->$m` of a method that
  returns a constant). The rule that survived: a floating call is fine if
  every sub it can reach is inert (no pinned node but Return, MemStart unread,
  no Call), or it is only the place of pinned stores (`slot() = 42`, 398).
- **A floating bless is everywhere.** All 33 in the corpus bless a fresh `{}`
  only the bless holds. That shape is safe; any other (`bless $h` with `$h`
  read elsewhere) is refused.
- **A floating fault needs a "nothing in between" walk, not a blanket rule.**
  Refusing every `/` with a variable divisor is too wide. Walk control back
  from each pinned user (or the arm end a Phi takes it from) to the pinned
  nodes the division is computed from; refuse only if an effect lies between.
  An eval's entry `$@ = ""` is not an effect for this walk, and a Divide
  marked `eval_id` is made after its eval's entry.
- **A versioned operand does not make `ref()` safe.** `ref($o)` of an `$o`
  kept in memory is `RefType[PadAccess[v]]`, a new node per version, and st7
  was still wrong: bless changes the object, not the variable, and the
  RefType still floats. I tried that tightening; it let st7 through.
- **Find the Phi that carries the variable, not any Phi stored to it.**
  `$_ = $i` in a loop stores `$i`'s Phi to `$_`. W1's Phi is the one whose
  back input is the value stored and whose entry input is the variable's
  value before the loop.
- **Diff the wire against the nearest right program before writing a rule.**
  lo3 (`local` in a loop left by `last`), the inner `local` of lo16, vp5
  (`$a[0] + ($a[0] = 10) + $a[0]`) and fl14 (`use warnings FATAL`) have wires
  byte-identical to programs chalk compiles right. No chalk-side rule can
  split them. lo16's shape is narrow (a package store in an eval block that
  dies), so both are refused and ev12 went SAME -> REFUSED. The other three
  stay WRONG, listed in chalk's `t/bootstrap/ir/audit-probes.t`.

**How to apply:** when the producer fixes a class (pins the list assign,
reads the package scalar through memory), delete the matching WireCheck
rule and rerun `tools/audit-probes.pl`; the probes it refused should turn
SAME, and `--update` records it. The probe test fails on any verdict that
leaves `t/data/audit-probes/BASELINE.tsv`, in either direction.

**Not closed by this:** W9 is refused only where B::SoN stamps the inner
element `Undef`; a nested read of a key that happens to be missing at run
time still does not autovivify. `qx` still floats (3 corpus cases). A die
of a scalar whose stamp is unknown is refused whenever the program has an
eval, which is wider than "a reference".

Related: [[a-silent-drop-is-worse-than-a-refusal]],
[[a-refusal-test-must-name-its-cause]],
[[a-list-assign-into-an-aggregate-is-placed-or-refused]]
