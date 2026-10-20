---
name: env-on-path-is-a-stub
description: "~/.local/bin/env shadows /usr/bin/env and silently runs nothing; `flock lock env VAR=1 cmd` exits 0 with no output"
metadata:
  node_type: memory
  type: reference
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-10-17T00:42:35.947Z
---

On this machine `/home/perigrin/.local/bin/env` comes first on the standard PATH and is not coreutils env: `env FOO=1 cmd` runs nothing and exits 0. A locked ratchet run `flock heavy.lock env SON_RATCHET=1 prove ...` therefore "passed" with empty output, and an agent trusted two such runs before noticing (2026-10-17).

**How to apply:** write `/usr/bin/env` (or `VAR=1 cmd` in a shell) in any command, and check a run's output contains `Result:` before quoting it. Related: [[a-sweeps-absence-is-not-evidence]], [[verify-the-harness-before-reading-its-output]].
