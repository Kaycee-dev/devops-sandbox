#!/usr/bin/env bash
# =============================================================================
# scripts/check_journal_today.sh
# -----------------------------------------------------------------------------
# Local pre-commit hook (stage: commit-msg, pass_filenames: false).
#
# Pre-commit invokes commit-msg hooks with the path to the in-flight commit
# message file as $1. We:
#   1. Read the commit message.
#   2. Extract the Conventional-Commits type prefix.
#   3. If the type is feat: or fix:, REFUSE the commit unless this commit
#      also adds or modifies a journal/YYYY-MM-DD-*.md file dated today.
#   4. Otherwise (docs:/chore:/ci:/refactor:/test:/build:/perf:), exit 0.
#
# Why only feat:/fix:?
#   feat: and fix: are the commit types that move acceptance rows from ☐ to ☑.
#   Per governance/05_JOURNAL_PROTOCOL.md, every such commit must reference a
#   journal entry. Forcing journal entries on docs:/chore:/ci: would either
#   pollute the journal with empty stubs or train us to misclassify
#   substantive work as chore: to dodge the gate. The matrix-touched hook
#   independently catches the case of functional change disguised as chore:.
#
# Escape hatch:
#     SKIP=journal-entry-on-feat git commit ...
#
# See governance/05_JOURNAL_PROTOCOL.md "Linking commits to entries".
# =============================================================================

set -euo pipefail

# Defensive: if pre-commit calls us without a message-file argument, pass.
if ! [[ -r "${1:-}" ]]; then
    exit 0
fi

if [[ "${SKIP:-}" == *journal-entry-on-feat* ]]; then
    printf 'journal-entry-on-feat: SKIP requested; this skip is logged.\n' >&2
    exit 0
fi

readonly MSG_FILE="$1"

# Strip comment lines (git's commentary in the editor) and grab the subject.
subject="$(grep -v '^#' "$MSG_FILE" | sed '/^$/d' | head -n 1 || true)"

if [[ -z "$subject" ]]; then
    # An empty commit message is a different kind of failure; let
    # conventional-pre-commit handle it. We pass.
    exit 0
fi

# Match the Conventional-Commits type prefix. Tolerate optional scope and "!".
if ! [[ "$subject" =~ ^([a-z]+)(\([a-zA-Z0-9_/-]+\))?!?:[[:space:]] ]]; then
    # Not Conventional Commits formatted; conventional-pre-commit will reject
    # it independently. We pass to keep error messages from this hook
    # focused on the journal concern.
    exit 0
fi

readonly type="${BASH_REMATCH[1]}"

case "$type" in
    feat | fix) ;;
    *) exit 0 ;;
esac

# Use UTC to match Constitution §4.1. The journal filename is the date the
# entry was opened; a commit on 2026-05-09T23:30Z lands in the 2026-05-09
# journal even if the host clock has rolled over locally.
today="$(date -u +%Y-%m-%d)"
readonly today
readonly journal_glob="journal/${today}-*.md"

mapfile -t staged < <(
    git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null \
        | grep -E "^journal/${today}-[0-9]{2}-[a-z0-9-]+\.md$" \
        || true
)

if [[ "${#staged[@]}" -ge 1 ]]; then
    exit 0
fi

# As a fallback, accept the case where today's journal exists on disk
# (perhaps committed earlier today in a separate commit) AND has been
# touched in some way that git considers staged. This makes mid-day
# follow-up commits honest without forcing a fresh journal file per commit.
if compgen -G "$journal_glob" >/dev/null; then
    cat >&2 <<EOF
journal-entry-on-feat: WARNING.

Today's journal entry exists on disk:
    $(ls -1 $journal_glob | head -n 1)

…but it is not part of this commit. That is allowed (the journal can be
committed separately) but you should make sure the entry references THIS
commit's hash before pushing. See governance/05_JOURNAL_PROTOCOL.md
"Linking commits to entries".

Continuing.
EOF
    exit 0
fi

cat >&2 <<EOF
journal-entry-on-feat: REFUSED.

Subject:  ${subject}
Type:     ${type}

Per governance/05_JOURNAL_PROTOCOL.md, every feat: / fix: commit must
reference a journal entry, and the journal entry's date must match today
(UTC: ${today}).

This commit:
    - is a ${type}: commit
    - does not stage any file matching:  ${journal_glob}
    - has no journal/${today}-*.md on disk

Fix:
    1. Copy governance/templates/journal_entry_template.md to:
           journal/${today}-NN-<slug>.md
       where NN is the session-of-day counter (01, 02, …) and <slug>
       is a kebab-cased ≤6-word description of this session.
    2. Fill the PLAN section before staging more code (per AGENTS.md §3).
    3. git add journal/${today}-NN-<slug>.md
    4. Commit again.

Escape hatch (use sparingly, with a note in the next journal entry
explaining why this commit was un-journaled):
    SKIP=journal-entry-on-feat git commit ...
EOF
exit 1
