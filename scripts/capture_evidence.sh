#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
OUT="${ROOT}/evidence/${STAMP}"
TRANSCRIPT="${OUT}/transcript.txt"

mkdir -p "$OUT"

run() {
    printf '$ %s\n' "$*" | tee -a "$TRANSCRIPT"
    "$@" 2>&1 | tee -a "$TRANSCRIPT"
}

cd "$ROOT"
run make up

create_output="$(make create NAME=evidence TTL=5 2>&1 | tee -a "$TRANSCRIPT")"
env_id="$(printf '%s\n' "$create_output" | awk '/^ENV_ID:/ { print $2; exit }')"
if [[ -z "$env_id" ]]; then
    printf '%s\n' "failed to parse env id" | tee -a "$TRANSCRIPT"
    exit 1
fi

run curl -fsSL "http://localhost:18080/${env_id}/health"
run make health
run make simulate "ENV=${env_id}" MODE=crash
sleep 95
run make health
run make simulate "ENV=${env_id}" MODE=recover
sleep 35
run make health
run make destroy "ENV=${env_id}"

printf 'Evidence bundle: %s\n' "$OUT" | tee -a "$TRANSCRIPT"
