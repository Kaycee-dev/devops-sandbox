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

usage() {
    printf '%s\n' "usage: create_env.sh --name <name> [--ttl-minutes <1-${MAX_TTL_MIN}>] [--env-id env-abc12345]" >&2
}

requested_env_id=""
name=""
ttl_minutes="$DEFAULT_TTL_MIN"
while (($#)); do
    case "$1" in
        --name)
            name="${2:-}"
            shift 2
            ;;
        --env-id)
            requested_env_id="${2:-}"
            shift 2
            ;;
        --ttl-minutes | --ttl)
            ttl_minutes="${2:-}"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$name" ]]; then
                name="$1"
            elif [[ "$ttl_minutes" == "$DEFAULT_TTL_MIN" ]]; then
                ttl_minutes="$1"
            else
                usage
                exit 2
            fi
            shift
            ;;
    esac
done

if [[ -z "$name" ]]; then
    printf 'Name: ' >&2
    read -r name
fi

if ! validate_env_name "$name"; then
    printf '%s\n' "invalid env name: ${name}" >&2
    exit 2
fi

if ! validate_ttl "$ttl_minutes"; then
    printf '%s\n' "ttl must be an integer from 1 to ${MAX_TTL_MIN}" >&2
    exit 2
fi

if [[ -n "$requested_env_id" ]] && ! validate_env_id "$requested_env_id"; then
    printf '%s\n' "invalid env id: ${requested_env_id}" >&2
    exit 2
fi

free_kb="$(df -Pk "$REPO_ROOT" | awk 'NR == 2 { print $4 }')"
if ((free_kb < 1048576)); then
    log ERROR create_env - "refusing create: less than 1 GiB free"
    exit 3
fi

existing_id="$(find_env_by_name "$name" || true)"
if [[ -n "$existing_id" && "$existing_id" != "$requested_env_id" ]]; then
    existing_url="$(read_state_field "$existing_id" url)"
    log INFO create_env "$existing_id" "name already active; returning existing env"
    printf 'ENV_ID: %s\nURL: %s\nTTL: %s minutes\n' "$existing_id" "$existing_url" "$(read_state_field "$existing_id" ttl_minutes)"
    exit 0
fi

if [[ -n "$existing_id" && "$existing_id" == "$requested_env_id" ]]; then
    existing_status="$(read_state_field "$existing_id" status || true)"
    if [[ "$existing_status" != "creating" ]]; then
        existing_url="$(read_state_field "$existing_id" url)"
        log INFO create_env "$existing_id" "name already active; returning existing env"
        printf 'ENV_ID: %s\nURL: %s\nTTL: %s minutes\n' "$existing_id" "$existing_url" "$(read_state_field "$existing_id" ttl_minutes)"
        exit 0
    fi
fi

env_id="${requested_env_id:-$(new_env_id)}"
created_at="$(ts)"
preexisting_state=0
if state_exists "$env_id"; then
    preexisting_state=1
    existing_created_at="$(read_state_field "$env_id" created_at || true)"
    if [[ -n "$existing_created_at" ]]; then
        created_at="$existing_created_at"
    fi
fi
network_name="sandboxnet-${env_id}"
container_name="sandbox-${env_id}-app"
url="${PUBLIC_BASE_URL}/${env_id}/"
name_url="${PUBLIC_BASE_URL}/${name}/"
internal_url="http://nginx/${env_id}/"
container_id=""
log_pid=""
conf_written=0
state_written=0
network_created=0
container_started=0

rollback() {
    local exit_code=$?
    if ((exit_code == 0)); then
        return 0
    fi
    log ERROR create_env "$env_id" "create failed; rolling back partial resources"
    if [[ -n "$log_pid" ]] && kill -0 "$log_pid" 2>/dev/null; then
        kill "$log_pid" 2>/dev/null || true
    fi
    if ((conf_written)); then
        delete_conf "$env_id" >/dev/null 2>&1 || true
    fi
    docker network disconnect "$network_name" sandbox-nginx >/dev/null 2>&1 || true
    if ((container_started)); then
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi
    if ((network_created)); then
        docker network rm "$network_name" >/dev/null 2>&1 || true
    fi
    if ((preexisting_state)); then
        update_state_field "$env_id" status error >/dev/null 2>&1 || true
    elif ((state_written)); then
        delete_state "$env_id"
    fi
    rm -rf -- "${LOGS_DIR:?}/${env_id}"
    exit "$exit_code"
}
trap rollback EXIT

log INFO create_env "$env_id" "starting create for name=${name} ttl=${ttl_minutes}"

if ! docker image inspect "$DEMO_IMAGE" >/dev/null 2>&1; then
    docker build -t "$DEMO_IMAGE" "${REPO_ROOT}/demo-app"
fi

docker inspect sandbox-nginx >/dev/null
docker network create \
    --label "sandbox.env=${env_id}" \
    --label "sandbox.role=network" \
    "$network_name" >/dev/null
network_created=1

container_id="$(
    docker run -d \
        --name "$container_name" \
        --network "$network_name" \
        --network-alias "$container_name" \
        --label "sandbox.env=${env_id}" \
        --label "sandbox.role=app" \
        --label "sandbox.created_at=${created_at}" \
        --cpus="$RESOURCE_CPUS" \
        --memory="$RESOURCE_MEMORY" \
        --pids-limit="$RESOURCE_PIDS" \
        --read-only \
        --tmpfs /tmp:size=64m \
        --security-opt no-new-privileges \
        --log-opt max-size=10m \
        --log-opt max-file=3 \
        -e "SANDBOX_ENV_ID=${env_id}" \
        -e "SANDBOX_NAME=${name}" \
        -e "PORT=${APP_PORT}" \
        "$DEMO_IMAGE"
)"
container_started=1

mkdir -p "${LOGS_DIR}/${env_id}"
: >"${LOGS_DIR}/${env_id}/app.log"
nohup docker logs -f "$container_id" >>"${LOGS_DIR}/${env_id}/app.log" 2>&1 &
log_pid="$!"

docker network connect "$network_name" sandbox-nginx >/dev/null 2>&1 || true
write_conf "$env_id" "$name"
conf_written=1

state_json="$(
    python3 - "$env_id" "$name" "$created_at" "$ttl_minutes" "$url" "$name_url" "$internal_url" "$network_name" "$container_id" "$DEMO_IMAGE" "$log_pid" <<'PY'
import json
import sys

env_id, name, created_at, ttl, url, name_url, internal_url, network, container_id, image, log_pid = sys.argv[1:]
state = {
    "id": env_id,
    "name": name,
    "created_at": created_at,
    "ttl_minutes": int(ttl),
    "status": "running",
    "url": url,
    "name_url": name_url,
    "internal_url": internal_url,
    "network": network,
    "container_id": container_id,
    "image": image,
    "labels": {
        "sandbox.env": env_id,
        "sandbox.role": "app",
        "sandbox.created_at": created_at,
    },
    "bg_pids": {"log_shipper": int(log_pid)},
    "last_outage": None,
    "consecutive_failures": 0,
}
print(json.dumps(state, indent=2, sort_keys=True))
PY
)"
write_state_atomic "$env_id" "$state_json"
state_written=1
append_history created "$env_id" "name=${name}" "ttl_minutes=${ttl_minutes}" "url=${url}"

trap - EXIT
log INFO create_env "$env_id" "created url=${url}"
printf 'ENV_ID: %s\nURL: %s\nNAME_URL: %s\nTTL: %s minutes\n' "$env_id" "$url" "$name_url" "$ttl_minutes"
