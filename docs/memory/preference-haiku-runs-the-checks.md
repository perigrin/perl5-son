# Preference: Haiku agents run the test checks (perigrin, 2026-10-31)

perigrin: "we should be using haiku for our test runners".

- The runs are plain shell jobs and cost no tokens. The cost is the main
  model polling, reading summaries, and restarting runs after a time
  limit (30 min default for a background job) or a worker restart.
- So dispatch each check (check.sh, the pin's three census runs, a suite
  rerun) to an Agent with `model: "haiku"`. It runs the job (use a long
  timeout, and rerun if killed) and returns only:
  - the suite files newly failing against the baseline;
  - the census counts and each case whose status changed;
  - the WRONG probes beyond the known six (ar, ar2, ar3, s5, a8, d0).
- The main model keeps diagnosis and fixes.

## Sonnet for obvious code changes (perigrin, 2026-10-31)

perigrin: "sonnet for obvious code changes".

- Dispatch mechanical, well-specified edits to an Agent with
  `model: "sonnet"`. Examples: a known-shape refusal guard, a test file
  from a template, a rename, one memory note, the pin's sed and commit.
  The brief gives the exact files, the change, and the test to run.
- Keep these on the main model: diagnosing a regression, choosing a
  representation or rule, and anything touching soundness (miscompile
  risk).
- Review the agent's diff before committing. The test-first rule still
  applies: its brief includes the failing test, or writing it first.
