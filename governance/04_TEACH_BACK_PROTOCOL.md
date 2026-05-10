# 04 — Teach-Back Protocol

The first goal of this build is a working sandbox platform. The second goal — equally weighted — is that **Kelechi can defend every decision in the codebase from memory**. That goal is met by teach-back blocks, written in the journal *before* the corresponding code lands.

## Why teach-back, not just comments

A code comment explains what a line does. A teach-back block explains why this approach was picked over the alternatives, what it costs, and how it could fail. Comments answer "what?". Teach-backs answer "why?" and "what if?". Interviewers ask the latter.

## When you write one

Write a teach-back block whenever a reasonable senior engineer would ask "why did you do it that way?". In practice that includes:

- Choosing a data structure or file format for state.
- Picking between two libraries or two compose-vs-script approaches.
- Deciding on a default value (timeout, TTL, port, retry count).
- Implementing any concurrency, signal handling, or atomicity guarantee.
- Implementing a security boundary or guard.
- Choosing what to log, what not to log, and at what level.
- Deciding what counts as an error vs a warning vs a noop.
- Picking a naming convention.

Skip a teach-back block when the choice is forced by the brief or the constitution (e.g., "we use UTC because §4.1 says so"). In those cases, cite the clause in a one-line comment in the code instead.

## The block format

Inline, in the active journal entry, immediately above the code change it justifies:

```markdown
### TEACH-BACK: <one-line decision in plain English>

**Context.** What problem we are solving in one or two sentences. Tie to a sprint task or acceptance row.

**Alternatives considered**
1. **<option A>** — <one-line trade-off; what we'd gain, what we'd lose>.
2. **<option B>** — <one-line trade-off>.
3. *(optional)* **<option C>** — <one-line trade-off>.

**Chosen** — **<option>**, because <one or two sentences tying to a constitution clause, an acceptance row, or a known-pitfall avoidance>.

**Failure modes**
- <what could still go wrong even with this choice>
- <how we would notice if it does>

**Reversal cost.** <How hard is it to switch later? Hours, days, or "not realistically possible after sprint N">.

**Citations.** <links to docs, blog posts, RFCs, MAN pages — only the ones that actually informed the decision>
```

## Worked example

Here is a real, fully-filled block for the atomic-state-write decision, which Kelechi will encounter in Sprint 2:

```markdown
### TEACH-BACK: Atomic state-file write via temp + fsync + rename

**Context.** The brief lists "writing state files non-atomically" as one of four named common
mistakes. We need `envs/$ENV_ID.json` to never appear half-written, even if `create_env.sh`
is `kill -9`'d mid-write or the VM loses power.

**Alternatives considered**
1. **Direct write** (`echo … > envs/$ENV_ID.json`). Simple, one line. Fails the brief outright;
   any interrupted write leaves a half-file that the cleanup daemon will read and act on.
2. **Lock file + direct write.** Closer to safe, but the lock does not prevent partial writes
   from being visible to a reader on a different process — POSIX `O_APPEND` semantics don't
   help here, and our reader is `cat`/`jq`, not flock-aware.
3. **Temp file + `mv` (no fsync).** Atomic *rename* is POSIX-guaranteed, but without `fsync`
   on the temp file the *contents* may not be on disk before the rename completes. On a power
   loss we could rename to a zero-byte file.
4. **Temp file + `fsync` + `mv`.** True crash-safe write. Slightly slower; one extra syscall.

**Chosen** — option 4, because §2.2 of the constitution and the named brief pitfall both
demand it. The performance cost is negligible at our write rate (≤1 write per env per
lifecycle event).

**Failure modes**
- The directory entry's metadata is not itself fsync'd, so on crash the rename may not be
  visible. We accept this — the daemon's reconciler in B19 catches orphaned containers on
  next loop. To go further would require fsync on the parent dir, which we may add in a
  later iteration.
- A bug in the helper could write to the wrong path. Mitigated by a `bats` test that
  asserts the temp file matches `envs/.tmp.${ENV_ID}.*.json`.

**Reversal cost.** Trivial. The helper is one function in `platform/lib/state.sh`. Swapping
implementations is a one-file change.

**Citations.**
- LWN, "ext4 and data loss" (the rename-without-fsync class of bugs).
- POSIX rename(2) man page on atomicity guarantees.
- Constitution §2.2.
```

## Length and tone

A teach-back block is 8–25 lines. Shorter than that and it is probably skipping context. Longer than that and it is probably over-explaining. The tone is mid-level senior engineer talking to a peer — assume the reader knows Docker but not your specific architecture. No marketing voice; no hand-waving.

## How blocks become the blog post

Every teach-back block has a `### TEACH-BACK:` heading that is grep-able. The post-build blog is assembled by:

1. Concatenating journal entries in chronological order.
2. Lifting every `### TEACH-BACK` block, with its surrounding paragraph if any.
3. Adding section headers per sprint.
4. Light copy-edit.

If the agent writes teach-backs sloppily, the blog reads like a stream of disconnected technical notes. If the agent writes them well, the blog reads like a published engineering post — that is the goal.

## Anti-patterns

These are *not* teach-back blocks, even if they look like one:

- **The narrator-voice paragraph**: "I decided to use FastAPI because it's modern and async." (No alternatives. No failure modes. No reversal cost. Useless to interviewers.)
- **The comment-in-prose**: "This function reads the state file and returns the parsed JSON." (That is a docstring, not a teach-back.)
- **The inevitability claim**: "Atomic writes are the obvious choice." (Then why does the brief list the non-atomic version as a common mistake?)
- **The post-hoc rationalisation**: writing the block *after* the code, to look as if reasoning preceded action. The protocol requires the block to land before or with the code, in the same commit. The agent's commit graph is the proof.

## Verification

`make ship-check` greps every `journal/*.md` for `### TEACH-BACK:` and ensures there are at least 12 across the journal set, and that no journal entry from sprints 1–4 has zero teach-backs. (Sprint 0 and 5 may have zero; bootstrap and ship are largely not decision-heavy.) That count is a floor, not a target.
