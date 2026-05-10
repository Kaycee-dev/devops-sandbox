#!/usr/bin/env bash
# =============================================================================
# scripts/check_acceptance_matrix.sh
# -----------------------------------------------------------------------------
# Local pre-commit hook (stage: pre-commit, pass_filenames: false).
#
# Refuses any commit whose staged file set includes functional code under
# platform/, monitor/, nginx/, or Makefile UNLESS governance/03_ACCEPTANCE_CRITERIA.md
# is also staged in the same commit. The point: keep the traceability matrix
# honest — if you ship code, you tick (or explicitly amend) the rows it closes.
#
# Escape hatch:
#     SKIP=governance-matrix-touched git commit ...
# Pre-commit's framework already honours SKIP; this hook just emits a stderr
# notice when it is invoked but skipped, to leave a paper trail.
#
# See governance/03_ACCEPTANCE_CRITERIA.md and governance/05_JOURNAL_PROTOCOL.md.
# =============================================================================

set -euo pipefail

readonly MATRIX_PATH="governance/03_ACCEPTANCE_CRITERIA.md"
readonly WATCH_REGEX='^(platform/|monitor/|nginx/|Makefile$|scripts/check_acceptance_matrix\.sh$|scripts/check_journal_today\.sh$)'

# Pre-commit always sets PRE_COMMIT_HOOK_ID when it runs us; if SKIP listed our
# id, pre-commit short-circuits before exec'ing this script, so we never see
# the env var with our id. This block is a defensive nicety for direct
# invocation only (e.g. `bash scripts/check_acceptance_matrix.sh`).
if [[ "${SKIP:-}" == *governance-matrix-touched* ]]; then
    printf 'governance-matrix-touched: SKIP requested; this skip is logged.\n' >&2
    exit 0
fi

# Get the staged file list. pre-commit invokes us inside the repo with the
# index already populated; --cached reflects that.
mapfile -t staged < <(git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null || true)

if [[ "${#staged[@]}" -eq 0 ]]; then
    # Empty commit (e.g. --allow-empty) — nothing to enforce.
    exit 0
fi

functional_changed=0
for path in "${staged[@]}"; do
    if [[ "$path" =~ $WATCH_REGEX ]]; then
        functional_changed=1
        break
    fi
done

if [[ "$functional_changed" -eq 0 ]]; then
    exit 0
fi

matrix_changed=0
for path in "${staged[@]}"; do
    if [[ "$path" == "$MATRIX_PATH" ]]; then
        matrix_changed=1
        break
    fi
done

if [[ "$matrix_changed" -eq 1 ]]; then
    exit 0
fi

cat >&2 <<EOF
governance-matrix-touched: REFUSED.

This commit changes functional code under platform/, monitor/, nginx/, or the
Makefile, but does not touch:
    $MATRIX_PATH

Per governance/03_ACCEPTANCE_CRITERIA.md, every functional change must either
close one or more acceptance rows (☐ → ☑) or amend a row's reference cells.
Half-credit ticks are forbidden — see AGENTS.md §3 step 6.

Fix:
    1. Open $MATRIX_PATH.
    2. Tick rows whose Code, Make target, Postman/test, AND Journal columns
       all reference real, committed artefacts as of THIS commit.
    3. Re-stage the matrix:  git add $MATRIX_PATH
    4. Commit again.

Escape hatch (use sparingly, with a journal note explaining why):
    SKIP=governance-matrix-touched git commit ...
EOF
exit 1
