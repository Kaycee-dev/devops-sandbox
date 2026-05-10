# 05 — Journal Protocol

The journal is the **first draft of the engineering blog post**. It is written as the work happens, by the agent, in `journal/YYYY-MM-DD-NN-<slug>.md`. It is not optional, it is not a diary, and it is not a place to stash TODOs.

## Naming

```
journal/2026-05-09-01-bootstrap.md
journal/2026-05-09-02-skeleton-and-demo-app.md
journal/2026-05-10-01-lifecycle-scripts.md
journal/2026-05-10-02-daemon-and-monitor.md
journal/2026-05-11-01-outage-and-api.md
journal/2026-05-12-01-polish-and-ship.md
```

The two-digit suffix is the session-of-day counter, zero-padded. A new session within the same day starts a new file; entries are not appended to. The slug is kebab-cased and ≤ 6 words.

## Frontmatter (mandatory)

```yaml
---
date: 2026-05-09
session: 01
slug: bootstrap
sprint: 0
duration_minutes: 90
files_touched:
  - .gitignore
  - .pre-commit-config.yaml
  - .gitleaks.toml
  - journal/2026-05-09-01-bootstrap.md
acceptance_rows_closed: [A01, A56, B15, B16, C01, C02]
acceptance_rows_in_progress: []
---
```

`acceptance_rows_closed` is the list of rows in `03_ACCEPTANCE_CRITERIA.md` that this session moves from ☐ to ☑. It is the single most important line in the frontmatter — `make ship-check` cross-checks it against the matrix.

## Body sections (mandatory, in order)

```markdown
## PLAN

- One paragraph. What this session is for. Tie to the sprint plan.
- A bulleted list of concrete tasks for this session.
- Acceptance rows targeted (mirrors the frontmatter line for human readability).

## TEACH-BACKS

- Inline, with `### TEACH-BACK:` headings, per `04_TEACH_BACK_PROTOCOL.md`.
- One block per non-trivial decision made this session.
- Written before the corresponding code change, not after.

## NOTES

- Anything else worth recording: surprising error messages, links to docs that
  helped, half-formed ideas for future sprints. Bullet points are fine here.

## OUTCOMES

- What actually shipped. List of files created, scripts that now work, tests
  that now pass.
- Paste the Newman summary block from `make test-api` here, verbatim, in a
  fenced code block.
- Paste the `make ship-check` output here, verbatim.

## LEARNINGS

- 2–4 bullets. Things Kelechi did not know at the start of the session and
  knows now. These are the bullets that survive into the blog post.

## BLOCKERS

- Open issues, pending decisions, things that need a chat with the reviewer.
- If empty, write `none` — never delete the section.

## NEXT

- One paragraph. What the next session should do. Specific enough that
  Kelechi can pick up cold tomorrow without re-reading anything else.
```

## Cadence

One journal entry per working session. A "session" is a contiguous block of work, separated from the next session by ≥ 2 hours of break. If you crack open the laptop after dinner, that is a new session, even if the work continues yesterday's task. Sessions can be short (30 minutes is fine if you closed two acceptance rows).

## Linking commits to entries

Every commit body includes the journal entry filename:

```
feat(platform): atomic state-file writer

journal: 2026-05-10-01-lifecycle-scripts.md
closes: B01
```

`closes:` lists the acceptance rows the commit closes. The pre-commit hook validates the format.

## Voice

Write as if a stranger will read it next week, because they will. Specifically:

- **Past tense for what happened** ("I added", "the test caught"). Present tense for what is true ("the daemon loops every 60s").
- **First person singular** is allowed and encouraged. The agent is co-authoring with Kelechi; "we" is fine when both are involved, "I" when the agent acted alone.
- **No hedging fillers** — drop "basically", "essentially", "kind of", "for the most part". They make the post weaker.
- **Concrete numbers and excerpts**. "Newman: 31 of 31 passed in 4.2s" is better than "all tests passed". Paste real log lines, real errors, real elapsed times.
- **Show one wrong turn per entry.** A good engineering blog admits mistakes. If the session genuinely had no wrong turns, write that, but think hard before claiming it — usually there was at least one.

## What goes in the blog post (later)

After the project ships, Kelechi compiles the journal into a single tech post titled something like *"Building a self-service sandbox platform in 72 hours: a teach-back."* The compile script (not in scope for this pack but trivial to write later) does:

```
cat journal/*.md \
  | strip-frontmatter \
  | rewrap-headings-up-one-level \
  | extract-teach-backs-and-pin-as-sidebars \
  | drop-OUTCOMES-NEWMAN-blocks-into-collapsible-details \
  | de-duplicate-NEXT-and-PLAN-paragraphs
```

If the journal is written correctly, that pipeline produces a 4000–6000 word post with very little hand-editing. If it isn't, the post will read like notes. The journal protocol is therefore a future-self gift.

## Verification

- `make ship-check` ensures: every journal entry has the mandatory sections; every `acceptance_rows_closed` entry exists in `03_ACCEPTANCE_CRITERIA.md`; the union of `acceptance_rows_closed` across all journal entries equals the set of ☑ rows in the matrix.
- A diff between the matrix's ☑ set and the journal's union is shown on `make ship-check` failure, so the agent can see exactly which rows are claimed-but-unjournaled (or journaled-but-unticked).
