# A skip after a failure reports ok

**Lesson (2026-11-27):** a `plan skip_all` after a failed assertion in the same
subtest turns the failure into a skip, and prove reports the file ok. chalk's
son-loop-backedge.t hid a stale pre-wire-v2 fixture this way for weeks;
control-flow.t skipped 22 GREEN cases' checks with "no .ll emitted".

**Rule:** a guard on a failure must `die`, not skip. Keep `skip_all` only for a
real environment gap (no perl 5.42, lli, B::SoN). To find hidden ones, grep the
real run's TAP for `# skip`, not the source.

Fixed on chalk branch honest-skips (f0fa90f6..1429ea8b): 6 commits, 138 dormant
guards now die.
