from __future__ import annotations

import os
from datetime import datetime, timezone

from flask import Flask, Response, jsonify, request


app = Flask(__name__)


def utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def env_id() -> str:
    return os.getenv("SANDBOX_ENV_ID", "env-local")


def env_name() -> str:
    return os.getenv("SANDBOX_NAME", "local")


@app.after_request
def add_sandbox_headers(response: Response) -> Response:
    response.headers["X-Sandbox-Env"] = env_id()
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/")
def index() -> Response:
    message = f"sandbox {env_name()} ok\n"
    return Response(message, mimetype="text/plain")


@app.get("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "env_id": env_id(),
            "name": env_name(),
            "ts": utc_now(),
            "path": request.path,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
