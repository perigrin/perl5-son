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
