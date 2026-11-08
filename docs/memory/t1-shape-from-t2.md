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
| A tied aggregate's read is a pinned memory version | tie (27) | fixed (main walk, loops, if/ternary arms; not yet a short-circuit arm -- see below) |
| foreach over a tied array counts each pass | tie (27) | fixed |
| A package scalar written by a sub in ANY package is read anew | tie (27) | fixed (was main:: subs only) |
| `$h->{k} .= "x$i"` (multiconcat APPEND to an element) | tie test classes | fixed |
| Context.pm's TIESCALAR skips the tie's memory input | tie (27) | fixed (chalk) |
| Whole assign to a tied aggregate is a store into it | tie (27) | fixed (Assign into its container; T2 t2_aassign/t2_hassign) |
| Whole assign to a referenced pad aggregate is a store into it | tie (27) | refused by name -- next |
| A select (ternary) merges control when an arm pins | tie (27) | fixed (an arm that pins takes the If/Region path, 4172672) |
| A short-circuit (&&, ||, //) arm merges control when it pins | tie (27) | open (_short_circuit_as_branch drops ON_VALUE) |
| A call to an XS sub says so (Call `xs`) | PadWalker (perigrin: no Perl source) | fixed -- T2 refuses "<name> is XS"; B::SoN's PadWalker-specific refusal deleted |

## T2/Context.pm side (not T1)
- `$_[N]` binder: fixed in T2 (every read binds to its argument; an unread position is a placeholder).
- Slurpy tails: fixed in T2 -- `my ($c, @x) = @_` and `sub f ($c, @x)` alike (perigrin: identical) take @_ as one array; the slurpy target a copy from k. `@_` after shifts already worked.
- `sort` (string/numeric, either order) and list `reverse`: fixed in T2. A sort with its own comparator block is still refused.
- A hash read whose version precedes a package store but used after it.
- `keys %$r` / `values %$r`: fixed in T2 (an undef reference reads as an empty hash). A store through `%$r` (autovivify) still refused.

## Open questions
- Our own PadWalker? PerlOnJava ships one (Perl facade over Java runtime lexical metadata, for Reply and Devel::Cycle; checked 2026-11-08 at 6a83374). It costs a runtime that keeps lexical metadata. perigrin to decide; until then T2 refuses it as XS.
- XS generally follows PerlOnJava's model: a native implementation (as UNIVERSAL and tie are), else a pure-Perl fallback compiled like any code, else refused.

## Flakes to watch
- pvm 176 (a local hash element, chalk-found-gaps.md) was GAP once in a census (Context: "a store to an element while a read through a reference waits") and ROUNDTRIP in 52 reruns: a rare order dependence, not yet found.
