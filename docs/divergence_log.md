# Divergence Log

> An honest record of places where what we shipped differs from what the spec
> ideally wanted, and why. Entries are append-only.
>
> Format: one entry per divergence, dated, citing the governing rule and
> documenting the cost.

---

## How to add an entry

Copy the block below and append. Do not amend prior entries; if a divergence
is later resolved, append a new entry that closes the previous one by
filename and date reference.

```markdown
### YYYY-MM-DD — short title

**Governing rule.** <link to governance/NN_*.md §X.Y or quote from CURRENT_TASK>

**What we did instead.** <plain English; one paragraph>

**Why.** <constraint that forced the divergence — environmental, time, or
deliberate trade-off>

**Cost.** <what reviewers should know is missing or weaker, and where the
fallback is recorded — usually a journal entry or a known-pitfall row>

**Recovery plan.** <what would close the divergence; or "permanent — no plan"
if accepted forever>
```

---

## Entries

<!-- newest at the top -->

### 2026-05-09 — Three pre-commit hooks marked "(no files to check) Skipped" in Sprint 0

**Governing rule.** Sprint 0 instruction (chat): "All hooks must pass with zero skips. If any hook genuinely cannot run, log it in journal/ AND in docs/divergence_log.md with reason — but try hard before falling back."

**What we did instead.** Sprint 0's `pre-commit run --all-files` reports `(no files to check) Skipped` for three hooks: `hadolint` (Dockerfile linter), `ruff` (Python linter), `ruff-format` (Python formatter). The other twelve hooks ran and passed.

**Why.** These three hooks have no input to operate on yet because the bootstrap repo carries zero `Dockerfile`s and zero `*.py` files. This is a "no-matching-files pseudo-skip," not a deliberate user skip via `SKIP=<id>`. The hook is correctly configured, correctly installed, and correctly invoked — it simply has no files of its target language to lint.

**Cost.** None for Sprint 0. The hooks are still wired and will fire automatically the moment Sprint 1 lands `demo-app/Dockerfile` and `demo-app/app.py`. We have not weakened any gate; we have simply not yet laid down the artifacts the gate inspects.

**Recovery plan.** Sprint 1 ships `demo-app/Dockerfile` (multi-stage, non-root) and `demo-app/app.py` (Flask, `/health` endpoint). At that point hadolint, ruff, and ruff-format MUST report `Passed`, not `Skipped`. If any of them is still `Skipped` after Sprint 1, that is a real problem and warrants a new divergence entry.
