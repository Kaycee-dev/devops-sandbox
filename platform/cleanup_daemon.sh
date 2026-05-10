#!/usr/bin/env bash
set -Eeuo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
# shellcheck source=platform/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=platform/lib/log.sh
source "${LIB_DIR}/log.sh"
# shellcheck source=platform/lib/state.sh
source "${LIB_DIR}/state.sh"

cleanup_log="${LOGS_DIR}/cleanup.log"

daemon_log() {
    log "$@" >>"$cleanup_log" 2>&1
}

stop_daemon() {
    daemon_log INFO cleanup_daemon - "daemon stopped"
    exit 0
}

trap stop_daemon SIGTERM SIGINT

is_expired() {
    local file="$1"
    python3 - "$file" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        state = json.load(fh)
    created = datetime.fromisoformat(state["created_at"].replace("Z", "+00:00"))
    expires = created + timedelta(minutes=int(state["ttl_minutes"]))
except Exception:
    sys.exit(2)

now = datetime.now(timezone.utc).replace(microsecond=0)
sys.exit(0 if now > expires else 1)
PY
}

reconcile_orphans() {
    local cid env_id state_file
    while read -r cid env_id; do
        [[ -n "$cid" && -n "$env_id" ]] || continue
        state_file="$(state_path "$env_id")"
        if [[ ! -f "$state_file" ]]; then
            daemon_log WARN cleanup_daemon "$env_id" "orphan app container without state; removing"
            docker rm -f "$cid" >/dev/null 2>&1 || true
            append_history cleanup "$env_id" "action=removed_orphan_container"
        fi
    done < <(docker ps -a --filter "label=sandbox.role=app" --format '{{.ID}} {{.Label "sandbox.env"}}')

    for state_file in "${ENVS_DIR}"/env-*.json; do
        [[ -e "$state_file" ]] || continue
        env_id="$(basename "$state_file" .json)"
        if ! docker ps -aq --filter "label=sandbox.env=${env_id}" | grep -q .; then
            daemon_log WARN cleanup_daemon "$env_id" "state exists without app container; marking error"
            update_state_field "$env_id" status error || true
            append_history cleanup "$env_id" "action=marked_zombie_state"
        fi
    done
}

daemon_log INFO cleanup_daemon - "daemon started interval=${CLEANUP_INTERVAL_S}s"

while true; do
    reconcile_orphans
    for state_file in "${ENVS_DIR}"/env-*.json; do
        [[ -e "$state_file" ]] || continue
        env_id="$(basename "$state_file" .json)"
        if is_expired "$state_file"; then
            daemon_log INFO cleanup_daemon "$env_id" "ttl expired; destroying"
            bash "${REPO_ROOT}/platform/destroy_env.sh" "$env_id" >>"$cleanup_log" 2>&1 || true
            append_history cleanup "$env_id" "action=destroyed_expired"
        elif [[ $? -eq 2 ]]; then
            daemon_log WARN cleanup_daemon "$env_id" "invalid state json; skipping"
        fi
    done
    sleep "$CLEANUP_INTERVAL_S" &
    wait "$!"
done
