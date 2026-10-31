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
