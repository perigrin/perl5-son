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
