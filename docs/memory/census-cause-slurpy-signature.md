# Census cause: a signature's slurpy parameter (369 -> 370, pin 4bb8ce37)

**Cause:** "direct call passes N argument(s), too few for its signature".
It held 163: `my $mk = sub ($id, @rest) {...}; $mk->(4)`.

## What was wrong

- **Named subs.** chalk refused any slurpy signature by name ("a
  signature with a slurpy parameter is not lowered").
- **Anonymous subs.** Their declared list is not on the wire, so chalk
  counted the parameters the body reads. The slurpy's index then
  counted as a mandatory position, and `$mk->(4)` was "too few".
  Another shape crashed on the hole (`->index` on undef).

## What changed (chalk 4bb8ce37)

- A trailing `@`/`%` Parameter becomes `_args_slurpy`. It is not a
  position.
- The inliner binds the Parameter node itself to an array (or hash) of
  the arguments past the scalars. The existing `my ($a, @r) = @_`
  slurpy path already built these.
- Called with no arguments, the slurpy is empty.
- **Still refused by name:** an odd count into a slurpy hash, and too
  few for the scalars. Perl dies on both.

**Round-tripped:** 163.

## Still refused

- **231**, `method f(@g)`: methods are emitted functions with fixed
  formals, and the slurpy was dropped from `param_reprs` ("declares 0").
  Lowering it needs an array formal and a caller-built array.
