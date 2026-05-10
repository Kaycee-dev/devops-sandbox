# DevOps Sandbox — Guardrails & Governance Pack

This folder is the **contract between Kelechi and the coding agent** (Claude Code, Cursor, Windsurf, or whichever IDE-tool combination is driving). It is the only set of documents the agent is allowed to treat as authoritative for the Stage 5 build. The task brief itself lives at the root of this pack as `CURRENT_TASK` — verbatim, untouched, so neither human nor agent can claim "I didn't see that requirement."

The pack mirrors the conventions of `Kaycee-dev/hng14-devops-stage4A` (`AGENTS.md`, `journal/`, `policies/`, `history.jsonl`, `manifest.yaml`, proof-bundle scripts) and extends them with three new disciplines that the Stage 5 brief does not ask for explicitly but which raise the floor of the work:

1. **Teach-back as the agent codes** — every non-trivial design decision is narrated *before* the code is written, so that Kelechi learns the platform he is shipping rather than just running its tests.
2. **Live journaling** — every working session produces one journal entry that later compiles, with minimal editing, into a publishable engineering blog post. The blog is not an afterthought; it is generated as a side-effect of doing the work properly.
3. **Acceptance traceability** — every explicit *and implied* requirement in `CURRENT_TASK` is mapped to a section of code, a Make target, a Postman test, and a journal entry. Nothing is allowed to be implemented without being traced; nothing traced is allowed to be skipped.

## How to read this pack

Read in numeric order. The numbering is the dependency order — the agent cannot work on `02_SPRINT_PLAN.md` without first internalising `01_CONSTITUTION.md`, and so on.

| # | File | Purpose |
|---|------|---------|
| — | `AGENTS.md` | Master system prompt for the coding agent. Loaded at the top of every session. |
| — | `CURRENT_TASK` | Raw, verbatim Stage 5 brief. Ground truth. |
| 00 | `00_INDEX.md` | One-page map of the whole repo, generated and re-generated as work progresses. |
| 01 | `01_CONSTITUTION.md` | Non-negotiables. Things the agent may never do or skip, regardless of expedience. |
| 02 | `02_SPRINT_PLAN.md` | Phased, hour-budgeted build plan. Six sprints, each with entry/exit criteria. |
| 03 | `03_ACCEPTANCE_CRITERIA.md` | Every explicit and implied requirement, traced to code + test + journal. |
| 04 | `04_TEACH_BACK_PROTOCOL.md` | The pedagogy. How the agent narrates *why* before *what*. |
| 05 | `05_JOURNAL_PROTOCOL.md` | Live journaling spec. Format, cadence, blog-compile path. |
| 06 | `06_DEFINITION_OF_DONE.md` | Per-component and overall DoD checklists. |
| 07 | `07_DEVSECOPS_GUARDRAILS.md` | Secrets, image hardening, network isolation, supply-chain rules. |
| 08 | `08_DEMO_SCRIPT.md` | Beat-by-beat 3-minute walkthrough video script. |
| 09 | `09_KNOWN_PITFALLS.md` | Specific failure modes called out by the task brief plus implicit ones. |
| 10 | `10_API_CONTRACT.md` | OpenAPI-shaped spec that the Postman collection tests against. |

## Subfolders

- `templates/` — fill-in-the-blank skeletons for journal entries, teach-back blocks, PRs, README, and the architecture diagram.
- `policies/` — OPA Rego stubs for sandbox-create and outage guardrails (extra-credit, mirrors Stage 4A pattern).
- `postman/` — `DevOpsSandbox.postman_collection.json` plus Local and Server environment files. Newman-runnable.
- `ci/` — pre-commit, gitleaks, shellcheck, and a GitHub Actions workflow that runs the Postman pack against the live sandbox.

## How a session starts (every session, no exceptions)

1. Agent reads `AGENTS.md`. That document re-anchors it to this pack.
2. Agent reads `CURRENT_TASK` end-to-end. No skimming.
3. Agent reads `03_ACCEPTANCE_CRITERIA.md` and identifies which row(s) the session will close.
4. Agent opens a new journal entry from `templates/journal_entry_template.md` and writes the **plan** section before writing any code.
5. Agent codes, with teach-back blocks live in the journal as decisions are made.
6. Agent updates `03_ACCEPTANCE_CRITERIA.md` (flips status from ☐ to ☑ on closed rows).
7. Agent runs the Postman pack via `make test-api` and pastes the Newman summary into the journal entry's **outcomes** section.
8. Agent commits with a Conventional-Commits message that references the journal entry filename.

Sessions that skip step 4, 6, or 7 are **invalid sessions** and the work in them must be rolled back.

## How submission readiness is checked

`make ship-check` (defined in `02_SPRINT_PLAN.md`, implemented as part of the Makefile) runs every gate in this pack — Newman pass, pre-commit clean, gitleaks clean, shellcheck clean, all acceptance rows ☑, README diagram present, demo script rehearsed-flag set. It must exit 0 before the submission form is opened.
