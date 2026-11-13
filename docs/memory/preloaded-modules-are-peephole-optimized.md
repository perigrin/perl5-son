# Preloaded modules carry peephole-optimized ops

**Date:** 2026-11-13

B::SoN turns perl's peephole optimizer off when it loads (B/SoN.pm BEGIN),
so everything compiled after it has canonical ops (helem, aelem, pushmark).
A module loaded BEFORE that -- Carp, Exporter, loaded by the compiler's own
toolchain -- was compiled with the optimizer on: `multideref`, `padrange`,
`aelemfast`. OpMap maps multideref as "pops one, pushes a Subscript", which
is false for the aux-operand form: Carp's `trusts`, `_fetch_sub`,
`get_subname` died "Stack underflow" (INTERNAL ERROR), and `short_error_loc`
was refused for an `&&` whose right side seemed to leave no value.

**Fix:** `_recompile_preloaded` compiles a followed preloaded module again at
CHECK (`do FILE`, warnings off: each sub is redefined), peep suppressed as for
every other file. Not a module that loads XS of its own (XSLoader/DynaLoader
in its source); aliased core XS (`*is_utf8 = \&utf8::is_utf8`) is fine.

**How it was found:** the sub translated fine when copied into a probe, never
inside Carp. Diff the two optrees (B::Concise) -- the difference was
multideref vs helem. A `$SIG{__DIE__}` hook printing the FromOptree frames
(DieTrace, scratch) finds where a refusal fires.

**Lesson:** a probe that "translates fine" is compiled under B::SoN's rules;
a preloaded module is not. Reproduce module refusals in the module.

Also this round:
- `redo`/`last` in an if/else nested in an arm: the inner if/else returns
  `left`; an if/else or if-without-else arm walk opts in ($LEFT_OK) and takes
  it as an arm that left, its edges already recorded. Any other walk refuses.
- `substr($s, o, l) =~ s///` (and /ge): the part read, substituted, written
  back by the 4-argument substr. `substr($s, o) = X`: length($s) as the length.
- Negate is not numeric on a string (-"abc" is "-abc"): operand uncoerced,
  result Int/Num only for a number, else Scalar. Chalk's fallback had to box it.
- A file lexical array read in an s///ge body is a pure read (padav,
  aelemfast_lex); an unshared one is refused by name.

## A string eval of known code (task #47, 2026-11-13)

`defined &NAME` folds unless the program may change the sub. A string eval
used to count as "may change any undefined sub" -- and left a DEFINED one
folded true even when the eval undefined it (`eval 'undef &here'`: a silent
wrong answer). Now: an eval of unknown code is `*` (any sub, either way); an
eval of a constant string is compiled once as `sub { CODE }` in a probe
package, every stash diffed before/after and PUT BACK at once, its body walked
with the same scan. Only-defines -> `+Name` (or `+` for an unqualified name):
a defined sub stays known defined, an undefined one is unknown.

Still blocked (2026-11-13): the 300 Carp-blocked files stop on Carp's
`defined &threads::tid` because Test::More / IO / File::Spec carry evals of
UNKNOWN code (`eval "require $module"`). Proposed to perigrin, awaiting a
go-ahead (wire change): the producer folds and lists the subs holding those
evals (`defined_unless`); chalk refuses only if one is reachable.

## SubDefined: the question goes to the backend (2026-11-13, perigrin: "fix the producer and refuse in the appropriate place")

`defined &NAME` the producer cannot settle is no longer refused: it emits
SubDefined { name, answer (as compiled), unless [graphs whose run may change
it] }. The scan records WHERE each change is (`undef &`, glob bind, eval) and
now walks anonymous subs too. Chalk answers it in an Analysis pass from the
loader's reach -- not in the loader (perigrin: "it should be an optimization
pass"). Next: chalk docs/plans/2026-11-13-the-loader-only-loads.md (reach,
refusal and pruning out of the loader too). The 300 Carp-blocked files now
pass ret_summary and stop on Carp::caller_info.

## Carp, continued (2026-11-13)

- map/grep block of statements is the loop body (its leave runs on into the
  mapwhile past nulls); leftovers between its statements are still dropped.
- `$#a = N`: Call `arylen` target -> pinned `set_arylen` write; T2 models
  holes (absent = undef slot, payload 1) and routes exists / set-length
  through the container metaobject (tie: EXISTS / STORESIZE).
- `return` in `eval { }` leaves the EVAL: its own exit list, one way into
  the join per return; only the body's `local`s are undone. Chalk refuses it
  by name for now (T2 and fallback).
- Lesson: probes compiled with peep ON (plain `perl -MO=Concise`) show a
  different optree than B::SoN walks (nulls kept); check `->next` past nulls.
- Lesson: memory is tight -- a deparser runaway during a verify got another
  test killed (a false "new fail"); run probes under `ulimit -v`.
- Next: Carp::_fetch_sub / _univ_mod_loaded / trusts_directly read the
  symbol table as data (`for ($::{$p}) { ref \$_ eq 'GLOB' && *$_{HASH} }`).
