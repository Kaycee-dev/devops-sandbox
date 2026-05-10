#!/usr/bin/env bash
set -Eeuo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
# shellcheck source=platform/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=platform/lib/env_id.sh
source "${LIB_DIR}/env_id.sh"
# shellcheck source=platform/lib/log.sh
source "${LIB_DIR}/log.sh"
# shellcheck source=platform/lib/nginx_render.sh
source "${LIB_DIR}/nginx_render.sh"
# shellcheck source=platform/lib/state.sh
source "${LIB_DIR}/state.sh"

env_id="${1:-}"
if ! validate_env_id "$env_id"; then
    printf '%s\n' "usage: destroy_env.sh env-abc12345" >&2
    exit 2
fi

if ! state_exists "$env_id"; then
    log INFO destroy_env "$env_id" "not found, nothing to do"
    exit 0
fi

log INFO destroy_env "$env_id" "destroy starting"
update_state_field "$env_id" status destroying || true

network_name="$(read_state_field "$env_id" network || printf 'sandboxnet-%s' "$env_id")"

mapfile -t bg_pids < <(
    python3 - "$(state_path "$env_id")" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    state = json.load(fh)
bg = state.get("bg_pids", {})
if isinstance(bg, dict):
    for value in bg.values():
        if isinstance(value, int):
            print(value)
elif isinstance(bg, list):
    for value in bg:
        if isinstance(value, int):
            print(value)
        elif isinstance(value, dict) and isinstance(value.get("pid"), int):
            print(value["pid"])
PY
)

docker network disconnect "$network_name" sandbox-nginx >/dev/null 2>&1 || true

mapfile -t containers < <(docker ps -aq --filter "label=sandbox.env=${env_id}")
if ((${#containers[@]})); then
    docker rm -f "${containers[@]}" >/dev/null
fi

for pid in "${bg_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in $(seq 1 5); do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
done

docker network rm "$network_name" >/dev/null 2>&1 || true
delete_conf "$env_id" >/dev/null 2>&1 || log WARN destroy_env "$env_id" "nginx reload after delete failed"

if [[ -d "${LOGS_DIR}/${env_id}" ]]; then
    archive_dir="${ARCHIVED_LOGS_DIR}/${env_id}/$(ts)"
    mkdir -p "$archive_dir"
    cp -a "${LOGS_DIR}/${env_id}/." "$archive_dir/"
    rm -rf -- "${LOGS_DIR:?}/${env_id}"
fi

delete_state "$env_id"
append_history destroyed "$env_id"
log INFO destroy_env "$env_id" "destroy complete"
