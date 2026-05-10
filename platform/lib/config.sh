#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LIB_DIR}/../.." && pwd)"

ENV_FILE="${REPO_ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

MANIFEST_FILE="${REPO_ROOT}/manifest.yaml"

manifest_default() {
    local key="$1"
    awk -v want="$key" '
        /^defaults:/ { in_defaults = 1; next }
        /^[^[:space:]]/ { in_defaults = 0 }
        in_defaults && $1 == want ":" { print $2; exit }
    ' "$MANIFEST_FILE"
}

manifest_resource() {
    local key="$1"
    awk -v want="$key" '
        /^resources:/ { in_resources = 1; next }
        /^[^[:space:]]/ { in_resources = 0 }
        in_resources && $1 == want ":" { print $2; exit }
    ' "$MANIFEST_FILE" | tr -d '"'
}

DEFAULT_TTL_MIN="${DEFAULT_TTL_MIN:-$(manifest_default ttl_minutes)}"
MAX_TTL_MIN="${MAX_TTL_MIN:-$(manifest_default max_ttl_minutes)}"
INGRESS_PORT="${INGRESS_PORT:-18080}"
API_PORT="${API_PORT:-18081}"
CLEANUP_INTERVAL_S="${CLEANUP_INTERVAL_S:-60}"
HEALTH_INTERVAL_S="${HEALTH_INTERVAL_S:-30}"

DEMO_IMAGE="${DEMO_IMAGE:-$(manifest_default image)}"
APP_PORT="${APP_PORT:-$(manifest_default app_port)}"
RESOURCE_CPUS="${RESOURCE_CPUS:-$(manifest_resource cpus)}"
RESOURCE_MEMORY="${RESOURCE_MEMORY:-$(manifest_resource memory)}"
RESOURCE_PIDS="${RESOURCE_PIDS:-$(manifest_resource pids_limit)}"

ENVS_DIR="${REPO_ROOT}/envs"
LOGS_DIR="${REPO_ROOT}/logs"
ARCHIVED_LOGS_DIR="${LOGS_DIR}/archived"
NGINX_CONF_DIR="${REPO_ROOT}/nginx/conf.d"
# shellcheck disable=SC2034  # sourced by log.sh and Python-backed helpers
HISTORY_FILE="${REPO_ROOT}/history.jsonl"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://localhost:${INGRESS_PORT}}"

mkdir -p "$ENVS_DIR" "$LOGS_DIR" "$ARCHIVED_LOGS_DIR" "$NGINX_CONF_DIR" "$NGINX_CONF_DIR/.broken"
