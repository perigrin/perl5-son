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
