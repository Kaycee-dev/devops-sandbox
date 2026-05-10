---
date: 2026-05-10
session: 07
slug: readme-live-submission
sprint: 5
duration_minutes: 45
files_touched:
  - journal/2026-05-10-07-readme-live-submission.md
  - README.md
  - governance/03_ACCEPTANCE_CRITERIA.md
acceptance_rows_closed: [A58]
acceptance_rows_in_progress: []
---

## PLAN

Refresh the submission-facing README now that the platform is deployed on the GCP VM. The goal is to replace stale live-server placeholders, keep the video placeholder honest until Kelechi uploads the walkthrough, and verify the deployed VM before touching the live-server acceptance row.

- [x] Verify the live ingress/API endpoints at `34.77.247.217`.
- [x] Create or confirm a real live env name for the README curl example.
- [x] Replace README live-server placeholder and stale known-limitation text.
- [x] Mentally trace the Quick Start against a fresh clone and note any divergence.
- [x] Run local verification and commit the README update.

Targeted rows: A53, A54, A55, A58

## TEACH-BACKS

### TEACH-BACK: Keep the video placeholder until the upload exists

**Context.** The README currently has two submission placeholders. The live server can be verified from the deployed VM, but the walkthrough video is an external artifact that does not exist in the repo yet.

**Alternatives considered**
1. **Replace both placeholders now** — makes the README look finished, but would require inventing a video URL.
2. **Replace only the live-server placeholder and leave video pending** — keeps the README accurate and avoids a false submission artifact.

**Chosen** — **replace only the live-server placeholder**, because `CURRENT_TASK` requires a real Drive link for the walkthrough video and `01_CONSTITUTION.md` §9 forbids fabricating or leaking submission data.

**Failure modes**
- The README will still show a pending video line until Kelechi uploads the final file.
- If the live VM is later torn down, the README live URL becomes time-sensitive and must be updated post-grading.

**Reversal cost.** Low.

## NOTES

- Pre-existing local changes not touched this session: `.gitignore`, `CRISIS_PROMPT.md`, `files (1).zip`, and `files (1).zip:Zone.Identifier`.
- Quick Start trace: `cp .env.example .env && chmod 600 .env` satisfies preflight, `make up` builds/starts platform, `make create NAME=demo TTL=5` is supported by the Makefile, `curl http://localhost:18080/demo/health` matches the name route, and `make destroy ENV=<env-id>` uses the printed env ID.
- Live smoke env: `readme-live`, `env-4602e75f`, expires `2026-05-11T01:55:49Z`.
- The first local `make ship-check` run reformatted the pre-existing `.gitignore` change by adding its missing trailing newline. That file remains unstaged for Kelechi to keep or discard separately.

## OUTCOMES

```
$ curl -fsS -i http://34.77.247.217:18081/health
PASS - HTTP 200, API status ok
```

```
$ curl -fsS -i http://34.77.247.217:18080/readme-live/health
PASS - HTTP 200, X-Sandbox-Env: env-4602e75f
```

```
$ newman run postman/DevOpsSandbox.postman_collection.json --env-var baseUrl=http://34.77.247.217:18081
PASS
- 14 requests, 60 assertions, 0 failures
- average response time: 1825ms
```

```
$ make ship-check
PASS
- pre-commit run --all-files: passed
- bash ci/shellcheck.sh: passed
- make test-api: passed, 14 requests, 59 assertions, 0 failures
```

## LEARNINGS

- A README live smoke route should include both the fixed ingress URL and a recreate command because sandbox envs are intentionally TTL-bound.
- A58 needs a deployed Postman proof, not only a health endpoint curl.

## BLOCKERS

A57 remains blocked until Kelechi uploads the final walkthrough video and shares a public Drive link.

## NEXT

After this README live-server pass, record and upload the walkthrough video, then replace the remaining README video placeholder with the tested Drive link.
