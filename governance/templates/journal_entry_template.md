---
date: YYYY-MM-DD
session: NN
slug: short-kebab-case
sprint: <0|1|2|3|4|5>
duration_minutes: 0
files_touched:
  - path/to/file.ext
acceptance_rows_closed: []
acceptance_rows_in_progress: []
---

## PLAN

<!--
One paragraph: what this session is for and how it advances the sprint plan.
Then a bulleted list of concrete tasks for this session.
End with the acceptance rows targeted (mirrors frontmatter).
-->

- [ ] Task 1
- [ ] Task 2

Targeted rows: <e.g. A02, A03, A06, B01>

## TEACH-BACKS

<!--
Inline, with `### TEACH-BACK:` headings, one per non-trivial decision.
Use the format from 04_TEACH_BACK_PROTOCOL.md verbatim.
Write each block BEFORE the corresponding code change, not after.
-->

### TEACH-BACK: <decision in plain English>

**Context.** <one or two sentences>

**Alternatives considered**
1. **<option A>** — <one-line trade-off>
2. **<option B>** — <one-line trade-off>

**Chosen** — **<option>**, because <reason tying to constitution clause or acceptance row>.

**Failure modes**
- <what could still go wrong>

**Reversal cost.** <hours, days, or "expensive after sprint N">

**Citations.**
- <link>

## NOTES

<!--
Anything else worth recording: surprising error messages, links to docs that
helped, half-formed ideas for future sprints. Bullet points are fine here.
-->

## OUTCOMES

<!--
What actually shipped. Files, scripts, tests.
Paste Newman summary verbatim in a fenced block.
Paste `make ship-check` output verbatim.
-->

```
$ make test-api
<paste Newman summary here>
```

```
$ make ship-check
<paste output here>
```

## LEARNINGS

<!--
2–4 bullets. Things you did not know at the start of this session and know now.
These are the bullets that survive into the blog post.
-->

-

## BLOCKERS

<!--
Open issues, pending decisions, things that need a chat with a reviewer.
If empty, write `none` — never delete the section.
-->

none

## NEXT

<!--
One paragraph. What the next session should do. Specific enough that you can
pick up cold tomorrow without re-reading anything else.
-->
