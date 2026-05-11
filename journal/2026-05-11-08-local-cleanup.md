---
date: 2026-05-11
session: 08
slug: local-cleanup
sprint: 5
duration_minutes: 20
files_touched:
  - journal/2026-05-11-08-local-cleanup.md
  - .gitignore
  - governance/03_ACCEPTANCE_CRITERIA.md
acceptance_rows_closed: []
acceptance_rows_in_progress: [A56]
---

## PLAN

Clean the local repository state without deleting Kelechi's local files. The goal is to commit the `.gitignore` hygiene that should be shared, ignore local scratch/download artifacts that should stay private, and leave the worktree clean after push.

- [x] Add shared ignore rules for local prompt files, downloaded ZIPs, and Windows Zone.Identifier sidecars.
- [x] Keep local prompt/archive artifacts out of git.
- [x] Run `make ship-check`.
- [x] Commit, push, and confirm local status is clean.

Targeted rows: A56

## TEACH-BACKS

### TEACH-BACK: Ignore local artifacts instead of deleting them

**Context.** The dirty worktree contains local prompt files and a downloaded ZIP bundle, none of which are platform source or required submission artifacts.

**Alternatives considered**
1. **Delete the files** — makes `git status` clean locally, but destroys local context Kelechi may still want.
2. **Commit the files** — preserves them, but pollutes the public repo with local prompts and downloaded archives.
3. **Commit ignore rules** — keeps useful local files on disk while making the repo clean and reproducible.

**Chosen** — **commit ignore rules**, because `CURRENT_TASK` requires secrets and runtime/local artifacts to stay out of git, and `.gitignore` is the correct shared mechanism for repeatable cleanliness.

**Failure modes**
- A future prompt file that should be public would need to avoid the `*_PROMPT.md` scratch naming pattern.
- A future ZIP that should be published must be force-added intentionally with a clear reason.

**Reversal cost.** Low.

## NOTES

- Local dirty inputs before this pass: `.gitignore`, `CRISIS_PROMPT.md`, `files (1).zip`, and `files (1).zip:Zone.Identifier`.
- `.gitignore` now treats `*_PROMPT.md`, `*.zip`, and `*:Zone.Identifier` as local-only artifacts.

## OUTCOMES

```
$ make ship-check
PASS
- pre-commit run --all-files: passed
- bash ci/shellcheck.sh: passed
- make test-api: passed, 14 requests, 59 assertions, 0 failures
```

## LEARNINGS

- Local scratch prompts and downloaded archives are repo hygiene issues, not submission artifacts.
- Ignoring `*:Zone.Identifier` keeps Windows download metadata from showing up in WSL-backed git status.

## BLOCKERS

none

## NEXT

After this cleanup lands, continue with the remaining external submission item: the walkthrough video link for A57.
