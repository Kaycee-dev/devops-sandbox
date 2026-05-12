---
date: 2026-05-12
session: 01
slug: clean-permission-repair
sprint: 5
duration_minutes: 35
files_touched:
  - Makefile
  - README.md
  - governance/03_ACCEPTANCE_CRITERIA.md
  - journal/2026-05-12-01-clean-permission-repair.md
acceptance_rows_closed: []
acceptance_rows_in_progress:
  - A50
---

## PLAN

Fix `make clean` so root-owned runtime logs archived by Docker-managed processes do not leave the operator stuck with manual `chown` commands. This amends the already-closed A50 cleanup behavior and keeps the Makefile target idempotent.

- [x] Reproduce/confirm the permission shape.
- [x] Patch `make clean` with a self-healing cleanup path.
- [x] Update README and acceptance matrix references.
- [x] Verify `make clean` against the current root-owned archive and run release gates.
- [x] Commit, push, and leave the repo clean.

Targeted rows: A50 amendment.

## TEACH-BACKS

### TEACH-BACK: Make cleanup privilege-aware

**Context.** `make clean` currently uses host-user `rm -rf`. That fails when archived logs are owned by root because deletion requires write permission on the parent directory, not just ownership of the child.

**Alternatives considered**
1. **Tell the operator to run `sudo chown` first** - works once, but violates the expectation that `make clean` is the cleanup interface.
2. **Teach `make clean` to retry cleanup inside a root Docker container** - keeps the public target idempotent and avoids interactive sudo.

**Chosen** - **Docker-backed cleanup retry**, because A50 requires `make clean` to wipe state/logs/archives, and the repo already depends on Docker for runtime operations.

**Failure modes**
- If Docker is unavailable and files are root-owned, `make clean` will still fail with a clear error.
- If the local platform image is absent, the retry needs a base image that is already likely to exist after normal platform use.

**Reversal cost.** Low.

**Citations.**
- `governance/CURRENT_TASK` Makefile requirement for `make clean`
- `governance/03_ACCEPTANCE_CRITERIA.md` A50

## NOTES

- The observed blocked parent was `logs/archived/env-86fa1e92`, owned by `root:root`.

## OUTCOMES

```
$ make clean
passed against a Docker-created root-owned fixture:
logs/archived/env-rootfix/2026-05-12T00:00:00Z/app.log

Post-clean runtime tree:
envs/.gitkeep
logs/.gitkeep
logs/archived
nginx/conf.d/.broken
nginx/conf.d/.gitkeep
```

```
$ make ship-check
trim trailing whitespace.........................................................Passed
fix end of files.................................................................Passed
check yaml.......................................................................Passed
check json.......................................................................Passed
check for merge conflicts........................................................Passed
check for added large files......................................................Passed
detect private key...............................................................Passed
mixed line ending................................................................Passed
Detect hardcoded secrets.........................................................Passed
ShellCheck v0.10.0...............................................................Passed
shfmt............................................................................Passed
Lint Dockerfiles.................................................................Passed
ruff.............................................................................Passed
ruff-format......................................................................Passed
governance acceptance matrix touched on functional changes.......................Passed

Newman summary:
requests: 14 executed, 0 failed
test-scripts: 28 executed, 0 failed
prerequest-scripts: 15 executed, 0 failed
assertions: 59 executed, 0 failed
duration: 16.1s
```

## LEARNINGS

- Root-owned directories can block deletion of child entries even when the child itself is user-owned.
- The cleanup target needs a postcondition check because `rm -rf` behavior under this WSL/Docker bind mount can still leave directories behind.
- A Docker-root fallback is appropriate here because the root-owned files are created by Docker-managed platform work, and the target stays scoped to ignored runtime paths.

## BLOCKERS

none

## NEXT

After this lands, use plain `make clean` for local runtime cleanup; no separate ownership repair should be needed for Docker-created log archives.
