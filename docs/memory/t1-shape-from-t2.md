---
name: The shape of T1 that T2 needs
description: perigrin's rule -- T2 work reveals what B::SoN's graph must say; a shortage is fixed in B::SoN, not worked around in T2. The ledger.
type: project
---
perigrin (2026-11-07): "Part of getting T2 to work is to understand better the
shape of T1 we need ... if there is a shortage there we fix B::SoN." Then: "Or
let's fix them" -- workarounds found are to be fixed, not kept.

**Why:** T2 lowers only what the graph says; a fact the graph leaves out
(an effect, an order, a site) cannot be recovered downstream.
**How to apply:** when T2 refuses or a test needs rewriting to dodge B::SoN,
find which side owns it; if the graph cannot say it, change B::SoN, with a
test there that failed first.

## Ledger (what T1 must say)
| Requirement | Found by | Status |
|---|---|---|
| An eval's end is a memory version | eval/try (slice 21) | fixed |
| A method call carries file/line | perl's dies (22) | fixed |
| `$o->A::m` is a method Call named A::m (method_redir) | qualified names (23) | fixed |
| tie/untie are ordered memory effects | tie (27) | fixed |
| A tied aggregate's read is a pinned memory version | tie (27) | fixed (main walk, loops, if/ternary/short-circuit arms) |
| foreach over a tied array counts each pass | tie (27) | fixed |
| A package scalar written by a sub in ANY package is read anew | tie (27) | fixed (was main:: subs only) |
| `$h->{k} .= "x$i"` (multiconcat APPEND to an element) | tie test classes | fixed |
| Context.pm's TIESCALAR skips the tie's memory input | tie (27) | fixed (chalk) |
| Whole assign to a tied aggregate is a store into it | tie (27) | fixed (Assign into its container; T2 t2_aassign/t2_hassign) |
| Whole assign to a referenced pad aggregate is a store into it | tie (27) | fixed (in place, as a tied one; T2 t2_aassign/t2_hassign; confirmed 2026-11-08) |
| A select (ternary) merges control when an arm pins | tie (27) | fixed (an arm that pins takes the If/Region path, 4172672) |
| A short-circuit (&&, ||, //) arm merges control when it pins | tie (27) | fixed (the arm on its own Proj pins; its value is a Phi at the join -- an And over the arm's value FETCHed twice) |
| A call to an XS sub says so (Call `xs`) | PadWalker (perigrin: no Perl source) | fixed -- T2 refuses "<name> is XS"; B::SoN's PadWalker-specific refusal deleted |
| A read through a reference waiting across a package store | hash read across a package store (goal 3) | fixed in T2, narrowly: made at the store when its version is the statement just before, in the same block, and it flows into no ?:, &&, ||, // or phi -- there it reads (or dies) as perl's. Otherwise still refused. (Pinning every such read in B::SoN broke 19 deparse tests; backed out.) |
| A deref for a write autovivifies | `%$r` store (goal 5) | fixed -- a `my` scalar undef there becomes a fresh `{}`/`[]`; an element dereferenced for a write is `elem //= {}`/`[]` stored back (perl's OPpDEREF_HV/AV under OPf_MOD, ending in a write). shortcut: a read through an undef intermediate does not make it, as perl's does; nor a foreach over an undef element; nor an element inside a loop body (the deparser orders a pass's store against its reads) -- T2 stops loudly on a write through an undef element there (a push), never pushing into a stand-in |
| A scalar deref names its site and strict refs | `$$r` in an eval (goal 6) | fixed -- PostfixDeref `$` carries eval_id/file/line/strict, as a may-die divide; pinned where it stands only in an eval or try body (where its die is caught mid-way) |
| A shared variable says whether it is the file's | comparator over a program lexical (goal 4) | fixed -- PadAccess `file`: the program's, or one a named sub or the program's sort block reaches out to; a sub's own a closure captures is not. A program sort block shares the scalars it reads or writes (T2 compares in perl's order, below) |

## T2/Context.pm side (not T1)
- `$_[N]` binder: fixed in T2 (every read binds to its argument; an unread position is a placeholder).
- Slurpy tails: fixed in T2 -- `my ($c, @x) = @_` and `sub f ($c, @x)` alike (perigrin: identical) take @_ as one array; the slurpy target a copy from k. `@_` after shifts already worked.
- `sort` (string/numeric, either order) and list `reverse`: fixed in T2. A comparator (a block, a named sub) is a function of no arguments called per pair with the sort package's `$a`/`$b` set (t2_asort_by); `<=>` lowered (shortcut: a NaN gives 0, perl's undef). A comparator with an effect (a die, a print, a store, a call): fixed 2026-11-08 -- T2 sorts with pp_sort.c's merge sort (dynprep and merge, ported to C, compiled to IR, spliced into the prelude; a die longjmps out), so it calls the comparator on perl's pairs in perl's order (t2-sort-compares-in-perls-order). Context (T1) still sorts its own way: it refuses a comparator that prints or stores, by name; one that calls a sub with an effect it still lowers in its own order (only reached where T2 refuses the unit; open). A comparator reading a lexical of the program: fixed (file lexicals, below); of a sub: B::SoN refuses (a closure's cells, not yet).
- A read through a reference waiting across a package store: made at the adjacent store (see the ledger row).
- `keys %$r` / `values %$r`: fixed in T2 (an undef reference reads as an empty hash). A store through `%$r`: fixed by autovivify above.
- Nested data in T2 (an element holding a reference): `$h{x}{y}`, `$a[0][1]`, `@{$h{l}}` -- the element's reference; a read through undef is undef (t2_hget, t2_aderef_r); a push's own array through a reference is made before it.
- bless in T2: the class in the aggregate's header (%Array field 4), so an array blesses as a hash does; `bless` as a statement; `blessed`. Scalar and code references: refused by name.
- Scalar references in T2: `\$x` is the variable's heap cell (tag 9), `$$r` reads/stores through it; perl's dies (undef under strict, `Not a SCALAR reference`, a string under strict cut at 32) at the deref's site, its eval's to catch. Without strict a string is a name: a stop. A store through undef (perl vivifies): a stop.
- File lexicals in T2: one global each -- a scalar's slot, a hash's or array's reference made at first use (t2_ghash/t2_garray); `my $n; sub f { $n++ }` and a program sort block over `%h` lower. shortcut: a file lexical made anew in a loop is one variable here.
- Refused by name in T2 (acb609c9), where it once stopped at run time or answered wrong: a `$$r` where a reference T2 does not make may reach it (`\(@a)`, `\$_[0]`); a `\$x` in a loop body or an arm; a store through an element not made a hash or array first; an element's array read whole; an `&&`/`||` of a list; an `&$code;` sharing @_.
- Element autovivify (B::SoN) only in a `my %h`/`my @a` or a hash/array just made, found up the op tree.

## Open questions
- Our own PadWalker? PerlOnJava ships one (Perl facade over Java runtime lexical metadata, for Reply and Devel::Cycle; checked 2026-11-08 at 6a83374). It costs a runtime that keeps lexical metadata. perigrin to decide; until then T2 refuses it as XS.
- XS generally follows PerlOnJava's model: a native implementation (as UNIVERSAL and tie are), else a pure-Perl fallback compiled like any code, else refused.

## Flakes to watch
- pvm 176 (a local hash element, chalk-found-gaps.md) was GAP once in a census (Context: "a store to an element while a read through a reference waits") and ROUNDTRIP in 52 reruns: a rare order dependence, not yet found.

## T2-completion goal closed 2026-11-08 (perigrin's OK)

All eight items fixed or narrowed. perigrin accepted these remaining refusals by name; they stay open T2 work:

- Item 3: a hash read across a package store when the store is not the statement just before, or the read flows into ?:, &&, ||, // or a phi.
- Items 5/6: a store through an element not made a hash or array first; an array read whole through an element; a reference to a scalar in a loop body or an arm; a scalar deref where a reference T2 does not make may reach it.
- An && or || of a list; an & call of a code value sharing @_.
- Context (T1) lowers a comparator calling a sub with an effect in its own order (only where T2 refuses the unit).

## Maybe[T] = T|Undef, stage 1 (2026-11-08)

- Both lattices know `Maybe[T]` as rules, not tree edges (chalk `TypeLibrary`,
  producer `SoN::IR::Stamp`): T and Undef below it, it below Scalar, covariant;
  a join keeps a Maybe and absorbs Undef; a meet with T narrows to T.
- B::SoN stamps Print `Maybe[Boolean]` (perl: `&PL_sv_yes` or `&PL_sv_undef`).
  Chalk's loader keeps it; Context and T2 hold any `Maybe[...]` as a %Slot.
  Fixed: `defined(print NOWHERE ...)` read defined.
- Stage 2, open: `join(T, Undef)` with no Maybe on either side is still Scalar.
  Making it `Maybe[T]` is global (every undef-or-value merge) and its fallout is
  to be measured case by case.
- Next: defined-guard narrowing in B::SoN (in the arm where `defined X` holds,
  X loses its Undef; `defined X && X` is Boolean|T, so Boolean for a print).
