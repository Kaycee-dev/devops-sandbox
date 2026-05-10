#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=platform/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

validate_env_name() {
    [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$ ]]
}

validate_ttl() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= MAX_TTL_MIN))
}

state_path() {
    printf '%s/%s.json\n' "$ENVS_DIR" "$1"
}

write_state_atomic() {
    local env_id="$1"
    local json_payload="$2"
    local dest tmp
    dest="$(state_path "$env_id")"
    tmp="$(mktemp "${ENVS_DIR}/.tmp.${env_id}.$$.XXXXXX")"
    printf '%s\n' "$json_payload" >"$tmp"
    python3 - "$tmp" "$ENVS_DIR" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r+", encoding="utf-8") as fh:
    json.load(fh)
    fh.flush()
    os.fsync(fh.fileno())

dir_fd = os.open(sys.argv[2], os.O_DIRECTORY)
try:
    os.fsync(dir_fd)
finally:
    os.close(dir_fd)
PY
    mv -f "$tmp" "$dest"
    python3 - "$ENVS_DIR" <<'PY'
import os
import sys

dir_fd = os.open(sys.argv[1], os.O_DIRECTORY)
try:
    os.fsync(dir_fd)
finally:
    os.close(dir_fd)
PY
}

read_state_field() {
    local env_id="$1"
    local field="$2"
    python3 - "$(state_path "$env_id")" "$field" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    state = json.load(fh)

value = state
for part in sys.argv[2].split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    sys.exit(1)
if isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
PY
}

state_json_with_field() {
    local env_id="$1"
    local field="$2"
    local value="$3"
    python3 - "$(state_path "$env_id")" "$field" "$value" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    state = json.load(fh)

field = sys.argv[2]
value = sys.argv[3]
if field in {"ttl_minutes", "consecutive_failures"}:
    state[field] = int(value)
else:
    state[field] = value

print(json.dumps(state, indent=2, sort_keys=True))
PY
}

update_state_field() {
    local env_id="$1"
    local field="$2"
    local value="$3"
    write_state_atomic "$env_id" "$(state_json_with_field "$env_id" "$field" "$value")"
}

delete_state() {
    local env_id="$1"
    rm -f -- "$(state_path "$env_id")"
}

assert_app_container() {
    local target="$1"
    local role
    role="$(docker inspect --format '{{ index .Config.Labels "sandbox.role" }}' "$target" 2>/dev/null || true)"
    if [[ "$role" != "app" ]]; then
        printf 'refusing to simulate outage on platform container: %s\n' "$target" >&2
        return 2
    fi
}

state_exists() {
    [[ -f "$(state_path "$1")" ]]
}
