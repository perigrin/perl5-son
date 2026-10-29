# Census cause: tie (348 -> ?)

**Cause:** "cannot lower op=Call builtin tie" held 3 cases: 012, 415 and
416.
- 415 and 416 round-trip in probes.
- 012 now hits `$b->$name` (dynamic_method).

## A producer miscompile, refused (producer)

The walk folds a lexical's stored value into its reads, tie or no tie:
- `tie my $x, C; $x = 5; print $x` reached the wire as `print 5`. Perl
  calls STORE, and dies when C has none.
- `my $y = 1; tie $y, C; print $y` printed the 1, where perl calls FETCH.

`_refuse_tie_of_a_stored_lexical`: a tie of a padsv whose slot another
padsv with OPf_MOD touches in the same sub is refused. That covers a
store, `my` with a value, `\$x` and `$x++`. A `tied()` operand is exempt:
tied() takes its operand as an lvalue but does not store it.

## Chalk

- **`Analysis::_rewrite_tied_scalars`** (runs first in `infer`) applies to
  `tie my $x, CLASS, ARGS` when all of these hold:
  - the tie is on its graph's straight line (no Proj, Region or Loop back
    to Start);
  - `$x` is one PadAccess;
  - `$x` has at most one read occurrence (each read runs FETCH, and a
    method call is lowered once), and that read is not a
    store/ref/increment/untie;
  - each statement the read or a tied() reaches runs after the tie.

  It then rewrites:
  - the read becomes `Call(method FETCH, [tie])` stamped Scalar, coerced
    to `$x`'s stamp (the loader folds a Coerce into a Str-stamped
    PadAccess);
  - `tied($x)` becomes the tie node; `tied()` of what nothing ties
    becomes a Constant undef;
  - the tie is recorded in `%TIED`.

  Readers are found by scanning the graph's nodes. The consumer list
  missed the Coerce a print read.
- **Lowering a `tie`** (only one in `%TIED`) is a run-time dispatch of
  TIESCALAR. The invocant is the class *string*: `_lower_runtime_dispatch`
  now takes a Str invocant, matched by memcmp against each package
  declaring the sub, with no match exiting 255. The arguments are
  (class, ARGS), and `as => 'Scalar'` gives the final read. The node is
  then stamped Scalar, since its value is the object by its tag.
- **The dispatch arm reads the call's value at the call's stamp** after
  `_lower_call_direct`, which coerces to it. Reading at the callee's
  inline repr coerced twice.
- `_ensure_i1` reads Undef as false.

## Lessons

- A fact the producer folds away cannot be checked in chalk: the store to
  a tied variable was gone from the wire. Refuse where it is folded.
- Count a variable's read occurrences, not its reader nodes:
  `print $x, $x` is one reader.
- chalk's t/bootstrap/no-tie-in-the-subset.t greps lib/ for the tie
  operators, comments included. Write "a tie of x" and "a tied() of x",
  not the call forms.
