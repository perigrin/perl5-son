# Gap: the census doesn't compare stderr, so a lost die message is silent (2026-10-31)

perigrin: "it only *fails* if the comparison looks at STDERR otherwise
it's a silent bug".

**Found.** `sub chk ($n) { die "neg\n" if $n < 0; ... } chk(-1)`. Through
LLVM it exits 255 like perl, but "neg" never reaches stderr. A `die` in
an if branch outside an eval lowers to a bare `exit(255)`
("if branch N: die (abort)" in Context.pm). Pre-existing: seen on chalk
1e5230c1, before real calls.

**Why it was invisible.** tools/corpus-llvm-roundtrip.pl runs lli with
`2>/dev/null` (line 82) and compares stdout and the exit code only. So
every lost or wrong message, and any warning, round-trips.

**To do, as its own cause.**
1. Compare stderr in the census as well. Perl's messages add
   "at FILE line N." That needs a rule: compare exactly when the message
   ends in "\n" (perl adds no location then); otherwise compare with the
   location normalised, or teach chalk the file and line.
2. Expect new DIFFERS once stderr is compared. They are real bugs that
   were already there. Fix the die-in-a-branch message first.
