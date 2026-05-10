#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=platform/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

ts() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

log() {
    local level="$1"
    local component="$2"
    local env_id="$3"
    shift 3
    printf '%s %s %s %s  %s\n' "$(ts)" "$level" "$component" "${env_id:-"-"}" "$*" >&2
}

append_history() {
    local event="$1"
    local env_id="$2"
    shift 2
    mkdir -p "$(dirname "$HISTORY_FILE")"
    python3 - "$HISTORY_FILE" "$(ts)" "$event" "$env_id" "$@" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
record = {"ts": sys.argv[2], "event": sys.argv[3], "env_id": sys.argv[4]}
for item in sys.argv[5:]:
    if "=" not in item:
        continue
    key, value = item.split("=", 1)
    record[key] = value
with path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, separators=(",", ":")) + "\n")
PY
}
