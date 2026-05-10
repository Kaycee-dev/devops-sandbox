# 10 — API Contract

The Postman pack tests this contract. The FastAPI implementation matches this contract. If the contract and the implementation diverge, the contract wins — change the contract first, then the code.

## Base URL

Local: `http://localhost:18080` (the public ingress port, which fronts both the env URLs and the API; the API mounts at `/api/v1/`).

Server: `https://<your-deployed-host>` — same shape.

API path prefix: `/api/v1`.

## Authentication

If `API_TOKEN` is set in `.env`, every request must carry `X-API-Token: <token>`. Missing or wrong token → 401 with `{ "error": { "code": "unauthenticated", "message": "missing or invalid X-API-Token" } }`.

If `API_TOKEN` is unset, the API logs a startup warning and accepts unauthenticated requests. This is for local development only; the deployed server always sets the token.

## Common error shape

Every non-2xx response uses this shape:

```json
{
  "error": {
    "code": "<machine_code>",
    "message": "<human readable>",
    "details": {}
  }
}
```

Documented machine codes:

| Code | When |
|------|------|
| `validation_error` | 400 — body or query did not match the schema |
| `unauthenticated` | 401 — missing/invalid token |
| `not_found` | 404 — env id does not exist |
| `conflict` | 409 — name already in use (if reuse-by-name disallowed) |
| `precondition_failed` | 412 — pre-flight check failed (low disk, port collision, etc.) |
| `internal_error` | 500 — unhandled exception |
| `bad_gateway` | 502 — underlying script exited non-zero unexpectedly |

## State schema (ground truth for `envs/$ENV_ID.json`)

```json
{
  "id": "env-a3f9b2c1",
  "name": "demo",
  "created_at": "2026-05-09T13:42:08Z",
  "ttl_minutes": 30,
  "status": "running",
  "url": "http://localhost:18080/env-a3f9b2c1/",
  "network": "sandboxnet-env-a3f9b2c1",
  "container_id": "<docker container id, full sha>",
  "image": "sandbox-demo:1.0.0",
  "labels": {
    "sandbox.env": "env-a3f9b2c1",
    "sandbox.role": "app",
    "sandbox.created_at": "2026-05-09T13:42:08Z"
  },
  "bg_pids": {
    "log_shipper": 12345
  },
  "last_outage": null
}
```

`status` is one of: `creating | running | degraded | destroying | error`.

## Endpoints

### `POST /api/v1/envs` — create env

Request:
```json
{
  "name": "demo",
  "ttl_minutes": 30
}
```

- `name` required, `^[a-z][a-z0-9-]{0,31}$`.
- `ttl_minutes` optional, integer in `[1, 240]`, defaults to `30`.

Response **201 Created**:
```json
{
  "id": "env-a3f9b2c1",
  "name": "demo",
  "created_at": "2026-05-09T13:42:08Z",
  "ttl_minutes": 30,
  "ttl_remaining_seconds": 1800,
  "status": "running",
  "url": "http://localhost:18080/env-a3f9b2c1/"
}
```

Errors: 400 (validation), 409 (name conflict, if reuse disallowed), 412 (pre-flight failure), 500.

### `GET /api/v1/envs` — list active envs

Response **200 OK**:
```json
{
  "envs": [
    {
      "id": "env-a3f9b2c1",
      "name": "demo",
      "created_at": "2026-05-09T13:42:08Z",
      "ttl_minutes": 30,
      "ttl_remaining_seconds": 1640,
      "status": "running",
      "url": "http://localhost:18080/env-a3f9b2c1/"
    }
  ],
  "count": 1
}
```

Empty list:
```json
{ "envs": [], "count": 0 }
```

### `DELETE /api/v1/envs/:id` — destroy env

Response **204 No Content** (no body) on success.

Errors: 404 if id matches the regex but no state file exists. (We do not return 404 for malformed ids; that is also a 404 — see §5.4 of the security pack.)

### `GET /api/v1/envs/:id/logs` — last 100 lines of `app.log`

Response **200 OK**:
```json
{
  "id": "env-a3f9b2c1",
  "lines": [
    " * Serving Flask app 'app'",
    " * Running on http://0.0.0.0:5000",
    "127.0.0.1 - - [09/May/2026 13:43:01] \"GET /health HTTP/1.1\" 200 -"
  ],
  "truncated": false
}
```

`truncated: true` if the underlying log had more than 100 lines (we always returned the last 100).

Errors: 404 if env doesn't exist.

### `GET /api/v1/envs/:id/health` — last 10 health checks

Response **200 OK**:
```json
{
  "id": "env-a3f9b2c1",
  "current_status": "running",
  "consecutive_failures": 0,
  "checks": [
    { "ts": "2026-05-09T13:43:00Z", "http_status": 200, "latency_ms": 12 },
    { "ts": "2026-05-09T13:42:30Z", "http_status": 200, "latency_ms": 9 }
  ]
}
```

Errors: 404 if env doesn't exist.

### `POST /api/v1/envs/:id/outage` — trigger simulation

Request:
```json
{ "mode": "crash" }
```

`mode` is one of `crash | pause | network | recover | stress`.

Response **202 Accepted**:
```json
{
  "id": "env-a3f9b2c1",
  "mode": "crash",
  "applied_at": "2026-05-09T13:44:12Z"
}
```

Errors: 400 (mode invalid or missing), 404 (env doesn't exist), 412 (target is a platform container — should not happen via this API since we look up by env ID, but defence in depth).

## Versioning

The contract version is `v1`. Breaking changes go to `v2` and the OpenAPI doc lives at both `/api/v1/openapi.json` and `/api/v2/openapi.json`. We do not version-mid-flight on a single project; if Stage 6 demands a v2, that is a new sprint.
