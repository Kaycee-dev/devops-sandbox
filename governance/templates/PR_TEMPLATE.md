# <type>(<scope>): <subject in imperative mood>

<!--
Conventional Commits subject line. Types: feat | fix | chore | refactor | docs | test | ci | perf | build.
Subject < 72 chars. No trailing period.
-->

## What this PR does

<!-- 2–4 sentences. Past tense. Concrete. -->

## Why

<!-- 2–4 sentences. Tie to a constitution clause, acceptance row, or pitfall guard. -->

## Acceptance rows closed

<!-- List rows from 03_ACCEPTANCE_CRITERIA.md that move from ☐ to ☑ in this PR. -->

- A0?
- B0?

## Journal entry

<!-- The journal file added or appended to in this PR. -->

`journal/YYYY-MM-DD-NN-<slug>.md`

## Verification

<!-- Paste relevant output. Newman summary, ship-check, bats output. Real, not fabricated. -->

```
$ make ship-check
...
```

## Checklist

- [ ] All `### TEACH-BACK:` blocks for new decisions are present in the journal entry.
- [ ] Acceptance matrix updated (☐ → ☑).
- [ ] README updated for any public-surface change.
- [ ] No secrets in the diff (gitleaks clean).
- [ ] `make ship-check` exits 0 on this branch.

<!-- Breaking changes? Add a section named "Breaking changes" with a one-line migration note. -->
