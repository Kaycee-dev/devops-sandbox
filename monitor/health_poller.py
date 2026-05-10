from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(os.getenv("REPO_ROOT", Path(__file__).resolve().parents[1]))
ENVS_DIR = REPO_ROOT / "envs"
LOGS_DIR = REPO_ROOT / "logs"
HISTORY_FILE = REPO_ROOT / "history.jsonl"
INTERVAL = int(
    os.getenv("HEALTH_INTERVAL_S", os.getenv("HEALTH_INTERVAL_SECONDS", "30"))
)


def utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def load_state(path: Path) -> dict[str, object] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def atomic_write_json(path: Path, payload: dict[str, object]) -> None:
    tmp = path.with_name(f".tmp.{path.stem}.{os.getpid()}.json")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)
    dir_fd = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def append_history(event: str, env_id: str, **fields: object) -> None:
    record = {"ts": utc_now(), "event": event, "env_id": env_id, **fields}
    with HISTORY_FILE.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, separators=(",", ":")) + "\n")


def update_status(
    path: Path, state: dict[str, object], status: str, failures: int
) -> None:
    state["status"] = status
    state["consecutive_failures"] = failures
    atomic_write_json(path, state)


def poll(url: str) -> tuple[int, int]:
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            response.read()
            status = int(response.status)
    except urllib.error.HTTPError as exc:
        status = int(exc.code)
    except (urllib.error.URLError, TimeoutError, OSError):
        status = 0
    latency_ms = int((time.perf_counter() - started) * 1000)
    return status, latency_ms


def main() -> None:
    failures: dict[str, int] = {}
    print(
        f"{utc_now()} INFO health_poller -  monitor started interval={INTERVAL}s",
        file=sys.stderr,
        flush=True,
    )
    while True:
        for path in ENVS_DIR.glob("env-*.json"):
            state = load_state(path)
            if not state:
                continue
            env_id = str(state.get("id", path.stem))
            if state.get("status") in {"creating", "destroying", "error"}:
                continue
            base_url = str(state.get("internal_url") or state.get("url", ""))
            url = base_url.rstrip("/") + "/health"
            status, latency_ms = poll(url)
            log_dir = LOGS_DIR / env_id
            log_dir.mkdir(parents=True, exist_ok=True)
            with (log_dir / "health.log").open("a", encoding="utf-8") as fh:
                fh.write(f"{utc_now()} {status} {latency_ms}\n")

            if 200 <= status < 300:
                failures[env_id] = 0
                if state.get("status") == "degraded":
                    update_status(path, state, "running", 0)
                    append_history("recovered", env_id)
                continue

            failures[env_id] = failures.get(env_id, 0) + 1
            if failures[env_id] >= 3 and state.get("status") != "degraded":
                update_status(path, state, "degraded", failures[env_id])
                append_history(
                    "degraded", env_id, consecutive_failures=failures[env_id]
                )
                print(
                    f"{utc_now()} WARN health_poller {env_id}  marked degraded after {failures[env_id]} failures",
                    file=sys.stderr,
                    flush=True,
                )
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
