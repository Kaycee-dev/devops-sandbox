---
date: 2026-05-11
session: 09
slug: interview-prep
sprint: 5
duration_minutes: 75
files_touched:
  - journal/2026-05-11-09-interview-prep.md
  - docs/interview-prep-pack.md
  - README.md
acceptance_rows_closed: []
acceptance_rows_in_progress: []
---

## PLAN

Create a comprehensive interview preparation pack that maps the HNG14 Stage 5 task brief to the actual implementation. The pack should help Kelechi defend architecture, control flow, configuration, operational behavior, testing, security decisions, and likely follow-up questions under pressure.

- [x] Inspect the task brief and core implementation files.
- [x] Write a structured interview pack under `docs/`.
- [x] Run documentation-focused verification plus `make ship-check`.
- [x] Commit, push, and leave the repo clean.

Targeted rows: none; this is a training artifact for already-shipped requirements.

## TEACH-BACKS

### TEACH-BACK: Build the prep as a repo document

**Context.** The interview will test detailed ownership of the shipped system, not a one-off conversational answer. The prep needs to survive later review and match the codebase.

**Alternatives considered**
1. **Answer only in chat** - fast, but easy to lose and not tied to specific repo files.
2. **Create a committed `docs/` prep pack** - durable, versioned, and reviewable beside the implementation.

**Chosen** - **create a committed `docs/` prep pack**, because `AGENTS.md` defines teaching Kelechi to defend the platform as part of delivery, and a repo artifact is the most reliable way to drill from actual implementation details.

**Failure modes**
- If the code changes later, the prep pack must be refreshed or it can become stale.
- If it becomes too broad, Kelechi may memorize prose instead of understanding flows; the pack should emphasize mental models and drill questions.

**Reversal cost.** Low.

## NOTES

## OUTCOMES

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
assertions: 60 executed, 0 failed
duration: 14.7s
```

Notes:
- First `make ship-check` attempt failed because `pre-commit` was installed in `~/.local/bin` but not on PATH.
- Second attempt reached Newman but failed because the local API was not running.
- After `make up`, rerunning `PATH="$HOME/.local/bin:$PATH" make ship-check` passed.
- `make down` stopped all platform containers.
- `make clean` needed a one-time ownership repair for old root-owned ignored logs; cleanup then succeeded.

## LEARNINGS

- The best interview prep artifact is a task-to-code map: every claim needs a concrete file, command, or gate behind it.
- The shipped implementation has a few honest boundaries Kelechi should state clearly: single VM, Docker socket risk, OPA policy files present but not runtime-enforced, and in-memory monitor counters.

## BLOCKERS

none

## NEXT

After the prep pack lands, use it for timed oral drills and update the README video link once the walkthrough upload is ready.
