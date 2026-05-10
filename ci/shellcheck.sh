#!/usr/bin/env bash
# GENERATED — do not edit by hand. Source: governance/ci/shellcheck.sh
# Sync helper: cp governance/ci/shellcheck.sh ci/shellcheck.sh
# =============================================================================
# ci/shellcheck.sh
# -----------------------------------------------------------------------------
# Run shellcheck across every shell script in the repo with consistent flags.
# Used by both the pre-commit local fallback and CI.
#
# Usage:
#     ci/shellcheck.sh [path...]
#
# Exit codes:
#     0 — every script clean
#     1 — at least one shellcheck violation
#     2 — shellcheck binary missing
# =============================================================================

set -euo pipefail

if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck: command not found\n' >&2
    exit 2
fi

# Default scope: every .sh under platform/, monitor/, scripts/.
declare -a paths
if [[ "$#" -gt 0 ]]; then
    paths=("$@")
else
    mapfile -t paths < <(
        find platform monitor scripts \
            -type f -name '*.sh' 2>/dev/null \
            | sort
    )
fi

if [[ "${#paths[@]}" -eq 0 ]]; then
    printf 'shellcheck: no shell scripts to check\n'
    exit 0
fi

shellcheck \
    --severity=warning \
    --external-sources \
    --shell=bash \
    --format=tty \
    "${paths[@]}"
