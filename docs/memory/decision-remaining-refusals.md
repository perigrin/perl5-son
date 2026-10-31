# Decisions on the remaining census refusals (perigrin, 2026-10-31)

Walked through one at a time.

| Cases | What | Decision |
|---|---|---|
| 015, 290, 291 | String eval of code built at run time | Accept as known GAPs |
| 286, 287, 288 | Regex code blocks `(?{ })` | GAP until regex compiles to IR. G6 emits LLVM directly, with no IR to hold the block's graph. Long-term goal: regex is a sub-language compiled to IR. |
| 365, 366, 370 (014 later) | `qx`/`readpipe`, `glob` | Targets. `qx` via libc `popen`, `glob` via libc `glob(3)`, refusing patterns where perl's BSD glob differs. libc is already chalk's syscall layer (`print` uses it), as it is for Rust and Julia. 014 also needs `format`/`write` and `<DATA>`. |
| 292, 210 | String eval of a literal | Producer compiles it as a block eval (the "rare circumstance") |
| 091, 092, 129, 141, 144 | A value that is a count in scalar context and a list in list context | Fix in the producer: give returned values both faces |
| 205 | Loop memory with a `next` latch | Fix in the producer |
| 229 | Unicode characters | Honour the existing `%Str` enc field. Set it from `utf8::upgrade` and non-ASCII literals; length, substr and case then count characters. |
| 056 | `our @ISA` with `SUPER::` | Support it: a constant `@ISA` assignment gives the package's parent |
| 308 | Computed `goto $label` | Support it: a switch over the labels; perl dies on an unknown one |

All other refusals are chalk lowering work with no decision needed.

**Ceiling:** 430 minus 6 accepted GAPs = **424**, or 427 once regex compiles
to IR.

## Update 2026-10-31: context is a type question (perigrin)

perigrin, on 091/092/129/141/144: "Isn't this a type inference
question?" and "List|Scalar is equivalent to List".

- Values: a scalar is a one-element list, so the join of List and
  Scalar is List. A sub returning either is typed List. No intersection
  type is needed.
- Scalar context over a List isn't a function of the type: it's the
  producing op's rule (an array gives its count, a comma list its last
  element, a hash assign the right side's count, sort/grep/reverse
  their own). So the call site's `want` must choose the op's behavior.
  That means compiling (monomorphizing) a sub per calling context in
  chalk's analysis, not a producer-side "two faces" node.
- perigrin corrected: `sub f { %h = () }` returns Hash. Measured on
  perl 5.42 with `%h = (a => 1, a => 2)`: list context gives `(a 2)`
  (the hash's contents, so Hash is right), but scalar context gives 4,
  the right side's element count. `scalar(%h)` would give 1. So the type
  is Hash, and scalar context still follows the op's own rule, not the
  type's.
- Status: proposed, awaiting perigrin's go-ahead (asked 2026-10-31).
