# Census cause: a call of a sub no one defines (AUTOLOAD)

**Cause:** "direct call to X has no resolved callee". It held 011, 293, 294
and 409. Two separate shapes: AUTOLOAD (011, 409) and formats (293, 294, see
census-cause-formats.md).

**Round-tripped:** 409 (269 -> 270). 011 now hits "ref() of a GlobRef is not
lowered".

## What was done

- **Analysis** `_attach_autoload`: a direct Call with no metaobject gets its
  package's AUTOLOAD as its target, with `autoloads` set to the full name.
- **Lowering:** before inlining, the full name is stored in `$pkg::AUTOLOAD`
  (a string constant, boxed into the package slot).

## When it stays refused

- Anything that can define a sub at run time: a string eval (Coerce Str->Code),
  `require`, `do FILE`, or a store into a glob's code slot that Analysis did not
  bind. Perl would call that sub instead.
- `$AUTOLOAD` read outside AUTOLOAD. B::SoN does not put an unresolved call in
  memory, so the read is not ordered after the store: au6 printed "" for
  `main::x`. Refused per package.
- An undefined call from inside AUTOLOAD: inlining would not terminate.

## Lessons

- Cheapest safe guard against a missing memory edge: find who can observe the
  store, and refuse when anyone outside the inlined body can.

Test: chalk `t/bootstrap/ir/llvm-a-call-of-an-undefined-sub-runs-autoload.t`.
Probes au1-au9: ROUNDTRIP or refused by name.
