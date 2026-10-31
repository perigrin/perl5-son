# Census cause: real calls, not inlining (step 0; count unchanged at 379)

perigrin: "inlining is/was a premature optimization" and "real calls
should definitely come before use/require". See
decision-real-calls-not-inlining.md.

## What changed (chalk 5cf77a6a)

- **One decision, shared.** `_sub_has_define` (LLVM.pm) decides whether
  a sub has a define, and caches the answer in its registry entry. The
  emitter and every call site (`_recursive_sub_info` in Context.pm) read
  the same answer, so a body is never both emitted and inlined, which
  would duplicate its string globals and effects.
- **Who gets a define.** A signature sub (the registry holds no
  `uses_args` subs) whose parameters are Int, Num, Str or Boolean, whose
  return settles to one of those (trial settling now runs for any sub,
  not only one that calls itself), and whose body lowers on its own.
  Two subs calling each other work: the `deciding` and `settling`
  guards assume yes and the trial type.
- **A body narrower than its declaration.** `$n * 2` declared Num
  returns Int, the type callers were typed against. The first run
  emitted `ret double` while the caller added i64s, and lli refused it.
- **Still inlined.**
  - A call in an eval body, directly or through an inlined caller: a die
    in a define doesn't reach the eval's catch yet.
  - A sub with optional parameters (a default is computed in its body).
    pvm 008 and 030 regressed to GAP until this rule went in.
  - A call passing the wrong argument count, so perl's arity die and its
    refusal by name still apply (llvm-arity-is-perls.t caught it).
  - Subs that write a file lexical or read wantarray: their bodies don't
    lower alone, so they fail the trial.
- Test: llvm-a-direct-call-is-a-real-call.t (13). Red on 1e5230c1:
  no define, and ev/od refused as recursive.

**Round-tripped:** none new. The census stays at 379, with no case lost.
This is infrastructure.

**What's next:**
- B::SoN should turn `my ($a,$b) = @_`, `$_[N]` and successive `shift`s
  into numbered Parameter nodes, so non-signature subs get defines too.
- A die must unwind through a call, so eval bodies can call defines.
- Aggregate and Scalar parameters and returns.

**Seen on the way:** a `die` in an if branch outside an eval loses its
message (bare exit 255). It is silent because the census drops stderr.
See gap-census-ignores-stderr.md.

## @_ subs (chalk 3fd39658)

- The graph already connects @_ reads to their arguments. `my (...) =
  @_` is an Assign from ArgsSource. The shifts form a memory chain that
  keeps their order. `$_[N]` is Subscript(ArgsSource, Constant N). The
  Context.pm comment claiming otherwise was stale. No producer change
  was needed.
- `_args_from_reads` runs the inliner's `_collect_positional_arg_reads`
  on the sub's graph. It accepts when nothing writes @_, reads it as a
  list, takes a slurpy or leaves a hole, and each read has a scalar repr:
  its own stamp, or the one type its Coerce readers convert to. Count
  only value readers: the next shift takes a shift as memory, and that
  isn't a read.
- `_bind_define_args` sets the define body's `_arg_bind` to %argN. It's
  the inliner's own substitution, consulted before the cache.
- **A define's result takes its call's type.** Callers were typed from
  the call's stamp. `g($_[0] + 1)` was stamped Num while g returned Int,
  and lli refused an i64 in an fadd. llvm-a-call-to-a-sub-with-effects.t
  caught it.
- Still inlined: writes to `$_[N]` (they alias the caller), calls with
  a different argument count (perl does no arity check for @_ subs), and
  `shift // default` (refused before and after).
- Census: 379, unchanged, with no case lost.
