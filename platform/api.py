from __future__ import annotations

import hmac
import json
import os
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response


REPO_ROOT = Path(os.getenv("REPO_ROOT", Path(__file__).resolve().parents[1]))
ENVS_DIR = REPO_ROOT / "envs"
LOGS_DIR = REPO_ROOT / "logs"
API_LOG = LOGS_DIR / "api.log"
ENV_ID_RE = re.compile(r"^env-[0-9a-f]{8}$")
ENV_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$")
ALLOWED_MODES = {"crash", "pause", "network", "recover", "stress"}

app = FastAPI(title="DevOps Sandbox API", version="1.0.0")


def utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def api_log(level: str, message: str, env_id: str = "-") -> None:
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    with API_LOG.open("a", encoding="utf-8") as fh:
        fh.write(f"{utc_now()} {level} api {env_id}  {message}\n")


def error_response(
    status: int, code: str, message: str, details: Any | None = None
) -> JSONResponse:
    payload: dict[str, Any] = {"error": {"code": code, "message": message}}
    if details is not None:
        payload["error"]["details"] = details
    return JSONResponse(status_code=status, content=payload)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    _request: Request, exc: RequestValidationError
) -> JSONResponse:
    return error_response(
        422, "validation_error", "request validation failed", exc.errors()
    )


async def require_auth(request: Request) -> JSONResponse | None:
    token = os.getenv("API_TOKEN", "")
    if not token:
        return None
    supplied = request.headers.get("X-API-Token", "")
    if not hmac.compare_digest(supplied, token):
        return error_response(401, "unauthenticated", "missing or invalid X-API-Token")
    return None


def state_path(env_id: str) -> Path:
    return ENVS_DIR / f"{env_id}.json"


def load_state(env_id: str) -> dict[str, Any] | None:
    path = state_path(env_id)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        api_log("ERROR", "state json is invalid", env_id)
        return None


def iter_states() -> list[dict[str, Any]]:
    states: list[dict[str, Any]] = []
    for path in sorted(ENVS_DIR.glob("env-*.json")):
        try:
            states.append(json.loads(path.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            api_log("WARN", f"skipping invalid state file {path.name}")
    return states


def ttl_remaining_seconds(state: dict[str, Any]) -> int:
    created = datetime.fromisoformat(str(state["created_at"]).replace("Z", "+00:00"))
    expires = created + timedelta(minutes=int(state["ttl_minutes"]))
    return max(0, int((expires - datetime.now(timezone.utc)).total_seconds()))


def expires_at(state: dict[str, Any]) -> str:
    created = datetime.fromisoformat(str(state["created_at"]).replace("Z", "+00:00"))
    expires = created + timedelta(minutes=int(state["ttl_minutes"]))
    return expires.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_summary(state: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": state["id"],
        "name": state["name"],
        "created_at": state["created_at"],
        "expires_at": expires_at(state),
        "ttl_minutes": state["ttl_minutes"],
        "ttl_remaining_seconds": ttl_remaining_seconds(state),
        "status": state["status"],
        "url": state["url"],
    }


def run_script(args: list[str], timeout: int = 90) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def validate_name_ttl(payload: dict[str, Any]) -> tuple[str, int, list[dict[str, str]]]:
    details: list[dict[str, str]] = []
    name = str(payload.get("name", ""))
    ttl = payload.get("ttl_minutes", int(os.getenv("DEFAULT_TTL_MIN", "30")))
    if not ENV_NAME_RE.match(name):
        details.append(
            {"field": "name", "message": "must match ^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$"}
        )
    try:
        ttl_int = int(ttl)
    except (TypeError, ValueError):
        ttl_int = 0
    if not 1 <= ttl_int <= int(os.getenv("MAX_TTL_MIN", "240")):
        details.append({"field": "ttl_minutes", "message": "must be between 1 and 240"})
    return name, ttl_int, details


def find_env_id_in_stdout(stdout: str) -> str | None:
    match = re.search(r"ENV_ID:\s*(env-[0-9a-f]{8})", stdout)
    return match.group(1) if match else None


@app.middleware("http")
async def access_log(request: Request, call_next):
    auth_error = await require_auth(request)
    if auth_error is not None:
        api_log("WARN", f"{request.method} {request.url.path} unauthenticated")
        return auth_error
    response = await call_next(request)
    api_log("INFO", f"{request.method} {request.url.path} -> {response.status_code}")
    return response


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "component": "api", "ts": utc_now()}


@app.get("/api/v1/envs")
def list_envs() -> dict[str, Any]:
    envs = [state_summary(state) for state in iter_states()]
    return {"envs": envs, "count": len(envs)}


@app.post("/api/v1/envs", status_code=201)
async def create_env(request: Request):
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        return error_response(
            422,
            "validation_error",
            "invalid json body",
            [{"field": "body", "message": "invalid json"}],
        )
    name, ttl, details = validate_name_ttl(payload if isinstance(payload, dict) else {})
    if details:
        return error_response(
            422, "validation_error", "invalid create request", details
        )

    proc = run_script(
        ["bash", "platform/create_env.sh", "--name", name, "--ttl-minutes", str(ttl)],
        timeout=150,
    )
    if proc.returncode != 0:
        api_log("ERROR", f"create failed: {proc.stderr.strip()}")
        return error_response(
            502, "bad_gateway", "create_env.sh failed", {"stderr": proc.stderr[-1000:]}
        )
    env_id = find_env_id_in_stdout(proc.stdout)
    if not env_id:
        return error_response(500, "internal_error", "create did not return an env id")
    state = load_state(env_id)
    if not state:
        return error_response(500, "internal_error", "state missing after create")
    return JSONResponse(status_code=201, content=state_summary(state))


@app.delete("/api/v1/envs/{env_id}")
def destroy_env(env_id: str):
    if not ENV_ID_RE.match(env_id) or not state_path(env_id).exists():
        return error_response(404, "not_found", "env not found")
    proc = run_script(["bash", "platform/destroy_env.sh", env_id], timeout=90)
    if proc.returncode != 0:
        return error_response(
            502, "bad_gateway", "destroy_env.sh failed", {"stderr": proc.stderr[-1000:]}
        )
    return Response(status_code=204)


@app.get("/api/v1/envs/{env_id}/logs")
def get_logs(env_id: str):
    if not ENV_ID_RE.match(env_id) or not state_path(env_id).exists():
        return error_response(404, "not_found", "env not found")
    path = LOGS_DIR / env_id / "app.log"
    if not path.exists():
        return JSONResponse(content={"id": env_id, "lines": [], "truncated": False})
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return JSONResponse(
        content={"id": env_id, "lines": lines[-100:], "truncated": len(lines) > 100}
    )


@app.get("/api/v1/envs/{env_id}/health")
def get_health(env_id: str):
    state = load_state(env_id) if ENV_ID_RE.match(env_id) else None
    if not state:
        return error_response(404, "not_found", "env not found")
    path = LOGS_DIR / env_id / "health.log"
    checks: list[dict[str, Any]] = []
    if path.exists():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[
            -10:
        ]:
            parts = line.split()
            if len(parts) >= 3:
                checks.append(
                    {
                        "timestamp": parts[0],
                        "http_status": int(parts[1]),
                        "latency_ms": int(parts[2]),
                    }
                )
    return JSONResponse(
        content={
            "id": env_id,
            "current_status": state.get("status", "error"),
            "consecutive_failures": int(state.get("consecutive_failures", 0)),
            "checks": checks,
        }
    )


def outage_precheck(
    env_id: str, mode: str, state: dict[str, Any]
) -> JSONResponse | None:
    container_name = f"sandbox-{env_id}-app"
    platform_names = {
        "sandbox-nginx",
        "sandbox-api",
        "sandbox-daemon",
        "sandbox-monitor",
    }
    if container_name in platform_names or any(
        container_name.startswith(prefix) for prefix in platform_names
    ):
        return error_response(
            412, "precondition_failed", "target container is protected"
        )
    if mode not in ALLOWED_MODES:
        return error_response(
            422,
            "validation_error",
            "invalid outage mode",
            [{"field": "mode", "message": "invalid mode"}],
        )
    if state.get("status") not in {"running", "degraded"}:
        return error_response(
            412, "precondition_failed", f"env is in state {state.get('status')}"
        )
    return None


@app.post("/api/v1/envs/{env_id}/outage")
async def trigger_outage(env_id: str, request: Request):
    state = load_state(env_id) if ENV_ID_RE.match(env_id) else None
    if not state:
        return error_response(404, "not_found", "env not found")
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        return error_response(
            422,
            "validation_error",
            "invalid json body",
            [{"field": "body", "message": "invalid json"}],
        )
    mode = str(payload.get("mode", "")) if isinstance(payload, dict) else ""
    precheck = outage_precheck(env_id, mode, state)
    if precheck is not None:
        return precheck
    proc = run_script(
        ["bash", "platform/simulate_outage.sh", "--env", env_id, "--mode", mode],
        timeout=90,
    )
    if proc.returncode != 0:
        status = 412 if proc.returncode == 2 else 502
        code = "precondition_failed" if proc.returncode == 2 else "bad_gateway"
        return error_response(
            status, code, "simulate_outage.sh failed", {"stderr": proc.stderr[-1000:]}
        )
    return JSONResponse(
        status_code=202,
        content={"env_id": env_id, "mode": mode, "applied_at": utc_now()},
    )
