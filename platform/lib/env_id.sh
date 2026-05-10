#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=platform/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

validate_env_id() {
    [[ "${1:-}" =~ ^env-[0-9a-f]{8}$ ]]
}

new_env_id() {
    local id
    for _ in $(seq 1 40); do
        id="env-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
        if [[ ! -e "${ENVS_DIR}/${id}.json" ]] && ! docker ps -a --format '{{.Names}}' | grep -qx "sandbox-${id}-app"; then
            printf '%s\n' "$id"
            return 0
        fi
    done
    printf '%s\n' "unable to allocate unique env id" >&2
    return 1
}

find_env_by_name() {
    local name="$1"
    local file match
    for file in "${ENVS_DIR}"/env-*.json; do
        [[ -e "$file" ]] || continue
        match="$(
            python3 - "$file" "$name" <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        state = json.load(fh)
except (OSError, json.JSONDecodeError):
    sys.exit(1)

if state.get("name") == sys.argv[2] and state.get("status") not in {"destroying", "error"}:
    print(state.get("id", ""))
    sys.exit(0)
sys.exit(1)
PY
        )"
        if [[ -n "$match" ]]; then
            printf '%s\n' "$match"
            return 0
        fi
    done
}
