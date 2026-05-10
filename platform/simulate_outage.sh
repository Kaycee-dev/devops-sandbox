#!/usr/bin/env bash
set -Eeuo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
# shellcheck source=platform/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=platform/lib/env_id.sh
source "${LIB_DIR}/env_id.sh"
# shellcheck source=platform/lib/log.sh
source "${LIB_DIR}/log.sh"
# shellcheck source=platform/lib/state.sh
source "${LIB_DIR}/state.sh"

usage() {
    printf '%s\n' "usage: simulate_outage.sh --env env-abc12345 --mode crash|pause|network|recover|stress" >&2
}

env_id=""
mode=""
while (($#)); do
    case "$1" in
        --env)
            env_id="${2:-}"
            shift 2
            ;;
        --mode)
            mode="${2:-}"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if ! validate_env_id "$env_id"; then
    usage
    exit 2
fi

case "$mode" in
    crash | pause | network | recover | stress) ;;
    *)
        usage
        exit 2
        ;;
esac

if ! state_exists "$env_id"; then
    printf '%s\n' "env not found: ${env_id}" >&2
    exit 4
fi

container_name="sandbox-${env_id}-app"
assert_app_container "$container_name"

set_last_outage() {
    local value="$1"
    local state_payload
    state_payload="$(
        python3 - "$(state_path "$env_id")" "$value" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    state = json.load(fh)
state["last_outage"] = None if sys.argv[2] == "__none__" else sys.argv[2]
if sys.argv[2] == "__none__":
    state["status"] = "running"
print(json.dumps(state, indent=2, sort_keys=True))
PY
    )"
    write_state_atomic "$env_id" "$state_payload"
}

last_outage() {
    python3 - "$(state_path "$env_id")" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh).get("last_outage") or "")
PY
}

network_name="$(read_state_field "$env_id" network)"
log INFO simulate_outage "$env_id" "mode=${mode}"

case "$mode" in
    crash)
        docker kill "$container_name" >/dev/null
        set_last_outage crash
        ;;
    pause)
        docker pause "$container_name" >/dev/null
        set_last_outage pause
        ;;
    network)
        docker network disconnect "$network_name" "$container_name" >/dev/null
        set_last_outage network
        ;;
    stress)
        docker exec -d "$container_name" python -c 'import time; end=time.time()+30; x=0
while time.time()<end:
    x += 1'
        set_last_outage stress
        ;;
    recover)
        previous="$(last_outage)"
        case "$previous" in
            crash)
                docker start "$container_name" >/dev/null
                ;;
            pause)
                docker unpause "$container_name" >/dev/null 2>&1 || true
                ;;
            network)
                docker network connect "$network_name" "$container_name" >/dev/null 2>&1 || true
                ;;
            stress | "")
                :
                ;;
            *)
                :
                ;;
        esac
        set_last_outage __none__
        ;;
esac

append_history outage "$env_id" "mode=${mode}"
printf 'ENV_ID: %s\nMODE: %s\n' "$env_id" "$mode"
