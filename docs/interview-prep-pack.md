# HNG14 Stage 5 Interview Prep Pack

This pack is for a hard technical interview with the task designer. It is built
from the actual repository, not from memory. The goal is to help you explain the
system end to end, defend the trade-offs, and handle follow-up questions without
guessing.

Use this as your operating manual:

1. Read the "Core Story" until you can say it without looking.
2. Drill the lifecycle flows until you can draw them from memory.
3. Practice the Q&A out loud. Every answer should mention the exact file or
   mechanism that proves the claim.
4. Be honest about limitations. A reviewer can forgive a scoped limitation. They
   will punish overclaiming.

## Core Story

One-line pitch:

> `devops-sandbox` is a single-VM self-service sandbox platform. It creates
> short-lived isolated Docker environments, routes them through Nginx, streams
> logs, polls health, simulates outages, and destroys everything on demand or
> by TTL.

Thirty-second version:

> The platform runs four long-lived services with Docker Compose:
> `sandbox-nginx` as the public front door, `sandbox-api` as a FastAPI control
> plane, `sandbox-daemon` as the TTL cleanup worker, and `sandbox-monitor` as
> the health poller. When I create an environment, the platform generates an
> `env-xxxxxxxx` ID, creates a dedicated Docker network, starts one demo app
> container on that network with resource limits and labels, connects Nginx to
> that network, writes a route file under `nginx/conf.d/`, reloads Nginx, starts
> a log shipper, and writes runtime state atomically to `envs/<env_id>.json`.
> Destroy reverses every side effect and archives logs.

Two-minute version:

> The task asked for a miniature internal Heroku with a chaos toggle, all on one
> Linux VM. I split the system into a control plane and data plane. The control
> plane is Compose-managed: Nginx, API, cleanup daemon, and monitor. The data
> plane is created dynamically: each sandbox env is a Docker bridge network plus
> a demo app container. I avoided host-port allocation per env; every env is
> reached through path-based Nginx routes on the single ingress port.
>
> The source of runtime truth is the state file in `envs/`, and every update to
> that file goes through a temp-file, fsync, rename pattern so crashes do not
> leave half-written JSON. Nginx routes are generated, tested with `nginx -t`,
> and reloaded on create and destroy. Logs use the simple required approach:
> `docker logs -f` redirected into `logs/<env_id>/app.log`, with the background
> PID stored in state and killed on destroy.
>
> The API wraps the scripts rather than reimplementing all Docker orchestration
> in Python. That keeps the CLI and API paths consistent. The health monitor
> polls every active env every 30 seconds and marks it `degraded` after three
> consecutive failures. The outage simulator can crash, pause, disconnect,
> recover, or stress an app container, but it validates the env ID and refuses to
> act unless Docker labels show the target is a sandbox app.

## Files To Know Cold

| Area | File | What to say |
|---|---|---|
| Brief | `task_details.md` | The original Stage 5 task: lifecycle, daemon, Nginx, logs, health, outage, API, Makefile, README. |
| Governance | `AGENTS.md` | The repo process: read governance, journal, verify, acceptance traceability, teach-back. |
| Defaults | `manifest.yaml` | Source for default TTL, max TTL, image, app port, platform ports, resource limits. |
| Operator UX | `Makefile` | Single-command entry points: `up`, `down`, `create`, `destroy`, `logs`, `health`, `simulate`, `clean`, `test-api`, `ship-check`. |
| Compose | `docker-compose.yml` | Long-lived platform services and the Docker socket mount for API/daemon/monitor operations. |
| Front door | `nginx/nginx.conf` | Base Nginx server, `/health`, `/api/v1/` proxy, and `conf.d/*.conf` include. |
| Route generation | `platform/lib/nginx_render.sh` | Generated per-env route snippets, Docker DNS resolver, `nginx -t`, reload, broken config handling. |
| State | `platform/lib/state.sh` | Validation, atomic state writes, state updates, app-container assertion. |
| Env IDs | `platform/lib/env_id.sh` | `env-[0-9a-f]{8}` allocation and lookup-by-name idempotency. |
| Logging | `platform/lib/log.sh` | UTC timestamps and append-only `history.jsonl` records. |
| Create | `platform/create_env.sh` | Network, container, log shipper, Nginx route, state write, rollback trap. |
| Destroy | `platform/destroy_env.sh` | Kill log PID, remove labeled containers, remove network, reload Nginx, archive logs, delete state. |
| Cleanup | `platform/cleanup_daemon.sh` | TTL loop, orphan reconciliation, cleanup log, signal handling. |
| Health | `monitor/health_poller.py` | Poll loop, health logs, 3-failure degraded transition, recovery transition. |
| Outage | `platform/simulate_outage.sh` | Guarded modes: `crash`, `pause`, `network`, `stress`, `recover`. |
| API | `platform/api.py` | FastAPI endpoints, auth middleware, error shape, subprocess wrapping. |
| Demo app | `demo-app/app.py` | Flask `/` and `/health`, env headers, UTC timestamps. |
| API contract | `governance/10_API_CONTRACT.md` | Intended endpoint and error contract. |
| Gates | `.pre-commit-config.yaml`, `.github/workflows/ci.yml` | Local hooks and CI jobs: lint, build-test/Newman, Trivy. |
| Postman | `postman/DevOpsSandbox.postman_collection.json` | Linear contract flow: create, list, logs, health, outage, recover, errors, destroy. |
| Policies | `policies/*.rego` | OPA policy documents are present, but the running API mirrors the rules rather than invoking OPA. |

## Architecture Mental Model

The easiest way to explain the design is:

```text
External user
    |
    | http://host:18080/<env_id>/...
    v
sandbox-nginx
    |
    | dynamically connected to sandboxnet-env-*
    v
sandbox-env-xxxxxxxx-app

Operator/API user
    |
    | http://host:18081/api/v1/... or http://host:18080/api/v1/...
    v
sandbox-api
    |
    | subprocess -> platform/*.sh
    | docker socket -> Docker Engine
    v
Docker networks, containers, logs, Nginx reloads, state files
```

There are two planes:

- Control plane: Compose-managed services that live as long as the platform is
  up: `sandbox-nginx`, `sandbox-api`, `sandbox-daemon`, `sandbox-monitor`.
- Data plane: per-env resources created and destroyed dynamically:
  `sandboxnet-<env_id>`, `sandbox-<env_id>-app`, `nginx/conf.d/<env_id>.conf`,
  `envs/<env_id>.json`, and `logs/<env_id>/`.

Why this design:

- One ingress port avoids per-env host-port allocation.
- Per-env networks isolate sandbox apps from each other.
- Docker labels make cleanup robust because destroy can remove by
  `sandbox.env=<env_id>` even if container names drift.
- State files keep the implementation simple and inspectable for a single VM.
- Nginx route files are generated because hand-editing configs is exactly the
  kind of drift the brief warns against.

## What Happens On `make up`

Relevant file: `Makefile`.

Flow:

1. If `.env` is missing, `make up` copies `.env.example` to `.env`, sets mode
   `600`, prints a review message, and exits. This protects the secret file.
2. `make preflight` checks Docker access, Compose availability, `.env` mode,
   runtime directories, disk space, port collisions on `18080` and `18081`, and
   Nginx base config syntax.
3. It builds the demo app image as `sandbox-demo:1.0.0`.
4. It starts the Compose platform:
   `sandbox-api`, `sandbox-daemon`, `sandbox-monitor`, and `sandbox-nginx`.
5. Nginx health is available at `http://localhost:18080/health`.
6. API health is available at `http://localhost:18081/health`.

Interview answer:

> `make up` is not just `docker compose up`. It performs first-run `.env`
> handling, preflight checks, builds the demo image, then starts the platform
> services. The split matters because it catches port, disk, Docker, and config
> issues before creating runtime envs.

## What Happens On Create

CLI path:

```bash
make create NAME=demo TTL=5
# wraps:
bash platform/create_env.sh --name demo --ttl-minutes 5
```

API path:

```bash
curl -fsS -X POST http://localhost:18081/api/v1/envs \
  -H 'Content-Type: application/json' \
  -d '{"name":"demo","ttl_minutes":5}'
```

Detailed flow in `platform/create_env.sh`:

1. Load config from `.env` and `manifest.yaml`.
2. Parse `--name`, optional `--ttl-minutes`, optional `--env-id`.
3. Validate:
   - name: `^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$`
   - env ID: `^env-[0-9a-f]{8}$`
   - TTL: integer between `1` and `MAX_TTL_MIN`.
4. Refuse create if free disk under 1 GiB.
5. Check for an active env with the same name. If it exists, return that env
   instead of creating a duplicate. This is the idempotency decision.
6. Allocate `env-xxxxxxxx` if one was not supplied.
7. Set resource names:
   - network: `sandboxnet-<env_id>`
   - container: `sandbox-<env_id>-app`
   - env URL: `<PUBLIC_BASE_URL>/<env_id>/`
   - name URL: `<PUBLIC_BASE_URL>/<name>/`
8. Install a rollback trap so any mid-create failure removes partial resources.
9. Build the demo image if missing.
10. Create the per-env Docker network with labels.
11. Run the app container:
    - labels: `sandbox.env`, `sandbox.role=app`, `sandbox.created_at`
    - resource limits from `manifest.yaml`
    - read-only filesystem
    - tmpfs `/tmp`
    - no-new-privileges
    - environment variables for `SANDBOX_ENV_ID`, `SANDBOX_NAME`, `PORT`
12. Start log shipping:
    `nohup docker logs -f <container_id> >> logs/<env_id>/app.log 2>&1 &`
13. Connect `sandbox-nginx` to the env network.
14. Render the Nginx route for both `/<env_id>/` and `/<name>/`.
15. Run `nginx -t` and reload Nginx.
16. Write state atomically to `envs/<env_id>.json`.
17. Append a `created` event to `history.jsonl`.
18. Print `ENV_ID`, `URL`, `NAME_URL`, and `TTL`.

Strong answer to "why create writes state near the end":

> The shell create path writes the final `running` state after Docker, logs, and
> Nginx are ready. If something fails before that, the rollback trap removes
> partial resources and deletes any partial state. The API path pre-allocates a
> temporary `creating` state so an asynchronous create can be represented, then
> the shell script overwrites it with the final state.

## State File Schema

Runtime state lives in `envs/<env_id>.json` and is gitignored.

Important fields:

```json
{
  "id": "env-xxxxxxxx",
  "name": "demo",
  "created_at": "2026-05-11T12:00:00Z",
  "ttl_minutes": 5,
  "status": "running",
  "url": "http://localhost:18080/env-xxxxxxxx/",
  "name_url": "http://localhost:18080/demo/",
  "internal_url": "http://nginx/env-xxxxxxxx/",
  "network": "sandboxnet-env-xxxxxxxx",
  "container_id": "...",
  "image": "sandbox-demo:1.0.0",
  "labels": {
    "sandbox.env": "env-xxxxxxxx",
    "sandbox.role": "app",
    "sandbox.created_at": "2026-05-11T12:00:00Z"
  },
  "bg_pids": {
    "log_shipper": 12345
  },
  "last_outage": null,
  "consecutive_failures": 0
}
```

Status values to know:

- `creating`: API pre-created state while the shell script is still running.
- `running`: normal healthy or recently created state.
- `degraded`: monitor saw three consecutive failed health checks.
- `destroying`: API has accepted a destroy and is tearing down.
- `error`: reconciliation or create failure left a state that needs attention.

Atomic write answer:

> The platform never writes `envs/<id>.json` directly. The Bash helper writes a
> JSON payload to a temp file in the same directory, validates it with Python,
> fsyncs the file, fsyncs the directory, then renames it into place. The Python
> API and monitor use the same idea: write temp, flush/fsync, `os.replace`,
> fsync the directory. So readers see either the previous complete JSON or the
> next complete JSON, never a half-file.

## What Happens On Nginx Routing

Relevant files:

- `nginx/nginx.conf`
- `platform/lib/nginx_render.sh`

Base Nginx:

- listens on container port `80`, host port `18080`
- exposes `/health`
- proxies `/api/v1/` to `sandbox-api:18081`
- includes `/etc/nginx/conf.d/*.conf`

Per-env config:

- generated at `nginx/conf.d/<env_id>.conf`
- contains two route blocks:
  - `/<env_id>/`
  - `/<name>/`
- rewrites the prefix away before proxying to the app
- sets `X-Sandbox-Env`
- uses Docker DNS resolver `127.0.0.11`
- uses `set $upstream sandbox-<env_id>-app:<APP_PORT>` so Nginx re-resolves the
  upstream instead of locking to a stale container IP

Nginx safety:

> `write_conf` and `delete_conf` both call `reload_nginx`. Reload first runs
> `docker exec sandbox-nginx nginx -t`. If a generated config is invalid,
> `write_conf` moves it to `nginx/conf.d/.broken/` and returns failure instead
> of leaving Nginx with a bad route.

Follow-up answer: "How does one Nginx reach isolated env networks?"

> Each env has its own Docker bridge network. The app only lives on its env
> network. `sandbox-nginx` starts on the platform network, then create connects
> it to the env network. Destroy disconnects it. That makes Nginx multi-homed:
> one stable front door, many isolated backends.

## What Happens On Destroy

CLI path:

```bash
make destroy ENV=env-xxxxxxxx
```

API path:

```bash
curl -fsS -X DELETE http://localhost:18081/api/v1/envs/env-xxxxxxxx
```

Detailed flow in `platform/destroy_env.sh`:

1. Validate the env ID.
2. If the state file does not exist, log "not found, nothing to do" and exit 0.
   That is CLI idempotency.
3. Mark state as `destroying`.
4. Read the network name from state.
5. Read background PIDs from `bg_pids`.
6. Disconnect `sandbox-nginx` from the env network.
7. Remove all containers with label `sandbox.env=<env_id>`.
8. Terminate each background PID:
   - `TERM`
   - wait up to 5 seconds
   - `KILL` if still alive
9. Remove the env network.
10. Delete the generated Nginx config and reload Nginx.
11. Archive logs to `logs/archived/<env_id>/<UTC timestamp>/`.
12. Remove `logs/<env_id>/`.
13. Delete the state file.
14. Append `destroyed` to `history.jsonl`.

Important distinction:

> The CLI destroy is idempotent and exits 0 if state is missing. The API returns
> 404 on a second DELETE because the HTTP contract treats "already gone" as a
> missing resource. The Postman suite verifies that second DELETE returns
> `not_found`.

## Cleanup Daemon

Relevant file: `platform/cleanup_daemon.sh`.

What it does:

- runs as `sandbox-daemon` under Compose
- loops every `CLEANUP_INTERVAL_S`, default 60 seconds
- writes UTC logs to `logs/cleanup.log`
- traps `SIGTERM` and `SIGINT`
- reconciles orphan resources
- destroys expired envs by calling `platform/destroy_env.sh`

TTL logic:

> The daemon reads each `envs/env-*.json`, parses `created_at`, adds
> `ttl_minutes`, and compares with current UTC time. If now is greater than the
> expiration time, it calls destroy.

Orphan reconciliation:

- app container exists but state file is missing:
  - remove the orphan container
  - append cleanup history
- state file exists but no app container exists:
  - mark state `error`
  - append cleanup history

Interview answer:

> The daemon is deliberately not clever. It delegates actual teardown to the
> same destroy script the operator and API use, so cleanup follows one code path.
> That reduces drift and makes idempotency important.

## Health Monitor

Relevant file: `monitor/health_poller.py`.

What it does:

- runs as `sandbox-monitor`
- loops every `HEALTH_INTERVAL_S`, default 30 seconds
- reads `envs/env-*.json` at the top of every loop
- skips states `creating`, `destroying`, and `error`
- polls `<internal_url>/health`, which goes through Nginx
- writes one line per check to `logs/<env_id>/health.log`
- line format: `<UTC timestamp> <http_status> <latency_ms>`
- keeps an in-memory consecutive failure counter per env
- marks env `degraded` after 3 consecutive failures
- flips `degraded` back to `running` on the next success

Why poll through Nginx:

> The monitor polls the same route the user depends on, not just the container
> directly. That catches app failures and routing failures. If the container is
> healthy but Nginx cannot route to it, the platform should still mark the env as
> unhealthy from the user's point of view.

Follow-up: "What if the monitor restarts?"

> The in-memory counter resets, so a degraded transition may take another three
> failed polls after monitor restart. The state file still stores the current
> status and `consecutive_failures` once degraded is written, but the live
> counter is process-local. For Stage 5 that is acceptable; a Stage 6 improvement
> would persist per-env failure counters or derive them from recent health logs.

## Outage Simulation

Relevant files:

- `platform/simulate_outage.sh`
- `platform/lib/state.sh`
- `platform/api.py`
- `policies/sandbox_outage.rego`

Modes:

| Mode | Implementation | Recovery |
|---|---|---|
| `crash` | `docker kill sandbox-<env_id>-app` | `docker start` |
| `pause` | `docker pause sandbox-<env_id>-app` | `docker unpause` |
| `network` | `docker network disconnect <network> <container>` | `docker network connect` |
| `stress` | short Python CPU loop inside container | wait for loop to finish |
| `recover` | reads `last_outage` from state and reverses it | clears `last_outage` |

Guard:

> Before any Docker action, the script constructs `sandbox-<env_id>-app` and
> calls `assert_app_container`. That helper reads the Docker label
> `sandbox.role`; if it is not exactly `app`, the script refuses. The API also
> prechecks platform container names and allowed modes. This protects Nginx,
> API, daemon, and monitor containers from the outage toggle.

Honest implementation note:

> The Rego policy files document the intended OPA rules, but the running API
> mirrors those checks in Python/Bash rather than shelling out to `opa`. Do not
> claim OPA enforcement is active. Say the rules exist as policy artifacts and
> the same guard logic is enforced in code.

## Control API

Relevant file: `platform/api.py`.

Service:

- FastAPI app, served by Uvicorn on port `18081`
- direct base URL: `http://localhost:18081/api/v1`
- proxied base URL: `http://localhost:18080/api/v1`
- health endpoint: `/health`

Endpoints:

| Method | Path | Status | Purpose |
|---|---|---|---|
| `GET` | `/api/v1/envs` | 200 | List visible envs and TTL remaining |
| `POST` | `/api/v1/envs` | 201 | Create env by name and TTL |
| `DELETE` | `/api/v1/envs/{env_id}` | 204 | Destroy env |
| `GET` | `/api/v1/envs/{env_id}/logs` | 200 | Last 100 app log lines |
| `GET` | `/api/v1/envs/{env_id}/health` | 200 | Last 10 health checks |
| `POST` | `/api/v1/envs/{env_id}/outage` | 202 | Trigger outage mode |

Auth:

> If `API_TOKEN` is set, every request must include `X-API-Token`. The code uses
> `hmac.compare_digest` to avoid naive token comparison. If `API_TOKEN` is blank,
> auth is disabled for local development.

Error shape:

```json
{
  "error": {
    "code": "validation_error",
    "message": "invalid create request",
    "details": []
  }
}
```

Create behavior:

- validates JSON
- validates name and TTL
- if an env with the same name exists, returns that env summary with 201
- pre-writes `creating` state
- starts `platform/create_env.sh`
- waits a short sync window
- if the script is still running, returns the pending state
- if the script finishes, returns final state
- if script fails, marks state `error` and returns `502 bad_gateway`

Why shell out instead of pure Python:

> The shell scripts are the canonical lifecycle implementation. The API wraps
> them so CLI and HTTP paths use the same behavior: same validation helpers,
> same rollback, same Nginx reload, same destroy logic. Rewriting Docker
> orchestration in both Bash and Python would create drift.

## Make Targets Cheat Sheet

| Command | What it proves |
|---|---|
| `make up` | Platform services boot after preflight. |
| `make create NAME=demo TTL=5` | Env lifecycle create works from CLI. |
| `curl http://localhost:18080/demo/health` | Nginx route and demo app work. |
| `make logs ENV=env-xxxxxxxx` | App logs are queryable by env ID. |
| `make health` | State and health summary are visible. |
| `make simulate ENV=env-xxxxxxxx MODE=crash` | Chaos path can break app only. |
| `sleep 95 && make health` | Monitor catches 3 failed 30s polls. |
| `make simulate ENV=env-xxxxxxxx MODE=recover` | Recovery reverses last outage. |
| `make destroy ENV=env-xxxxxxxx` | Teardown removes resources and archives logs. |
| `make down` | Stops platform and destroys active envs where possible. |
| `make clean` | Removes runtime state/logs/generated confs, preserves tracked files and `.env`. |
| `make test-api` | Newman API contract passes. |
| `make ship-check` | Aggregate local gate before push/submission. |

## CI And Verification

Local gate:

```bash
make ship-check
```

It runs:

- `pre-commit run --all-files`
- `bash ci/shellcheck.sh`
- `make test-api`

Pre-commit hooks:

- whitespace and file hygiene
- YAML/JSON checks
- merge conflict detection
- large file check
- private key detection
- gitleaks secret scanning
- shellcheck
- shfmt
- hadolint
- ruff lint and format
- conventional commit messages
- local governance hooks

GitHub Actions jobs:

- `lint`: pre-commit, gitleaks, shellcheck, hadolint
- `build-test`: compose build, `make up`, wait for API, Newman, collect logs on failure, `make down`
- `trivy`: build image and scan `devops-sandbox-api:latest` for HIGH/CRITICAL vulnerabilities

Postman proves:

- list baseline
- create env
- list includes created env
- logs endpoint
- health endpoint
- crash outage
- recover outage
- invalid env log lookup returns 404
- invalid name returns validation error
- invalid outage mode returns validation error
- destroy
- second destroy returns 404
- final list returns to baseline

Strong answer:

> CI is not just syntax linting. The build-test job actually starts the platform,
> runs the Postman contract against it, and tears it down. The Trivy job scans
> the platform API image and fails on HIGH/CRITICAL issues.

## Security And Safety Decisions

Secrets:

- `.env` is gitignored.
- `.env.example` is committed with placeholders/blank defaults.
- `.dockerignore` excludes `.env`, runtime state, logs, and docs from image
  build context.
- gitleaks runs locally and in CI.

API token:

- optional locally
- enforced when `API_TOKEN` is set
- uses `X-API-Token`
- compared with `hmac.compare_digest`
- token value is not logged

Docker socket:

> The API container mounts `/var/run/docker.sock`, which is the biggest security
> trade-off. It gives the API enough power to operate Docker on the host. The
> mitigation is that the API exposes fixed typed endpoints only; it does not
> accept arbitrary shell commands. Inputs are regex-validated before scripts run.
> For a single-VM Stage 5 platform this is acceptable, but in production I would
> replace it with a narrower privileged worker or Docker API proxy with policy.

Sandbox container hardening:

- per-env app containers use resource caps from `manifest.yaml`
- `--read-only`
- `--tmpfs /tmp:size=64m`
- `--security-opt no-new-privileges`
- demo app image runs as non-root user
- app containers do not mount the Docker socket
- app containers do not bind host ports

Outage guard:

- API validates env status and mode.
- Bash validates env ID and mode.
- Bash asserts Docker label `sandbox.role=app` before acting.
- Platform container names are protected in API precheck.

Input validation:

- env names only allow lowercase letters, numbers, and hyphens with safe edges.
- env IDs must match `env-[0-9a-f]{8}`.
- TTL is bounded from 1 to max TTL.
- outage mode is an allowlist.

## Known Limitations To Say Out Loud

Say these plainly if asked:

- It is single-VM only. There is no scheduler, cluster, or remote Docker context.
- State is file-based. That is appropriate for a one-host assignment, but a
  multi-host version would use a database or orchestrator state store.
- The API uses the Docker socket. That is powerful and must be protected.
- OPA policies are present as policy artifacts, but the runtime guard is
  implemented directly in Python and Bash.
- Prometheus and Grafana were optional and not part of the core shipped path.
- `stress` uses a short Python CPU loop, not `stress-ng`.
- Health failure counters are in monitor memory; a monitor restart resets the
  live counter.
- The demo app is intentionally simple. The platform is what is being graded.

Do not say:

- "This is production-ready Kubernetes."
- "OPA is enforcing requests at runtime."
- "API token is always set in every environment."
- "The sandbox fully isolates hostile workloads."
- "The health monitor persists all counter state durably."
- "There is no security risk from the Docker socket."

## Task Requirement Map

| Task requirement | Implementation |
|---|---|
| `platform/create_env.sh` creates env | `platform/create_env.sh`, `platform/lib/*.sh` |
| unique env ID | `platform/lib/env_id.sh`, `env-` plus 8 hex chars |
| dedicated Docker network | `docker network create sandboxnet-<env_id>` |
| app label `sandbox.env` | `docker run --label sandbox.env=<env_id>` |
| state file | `envs/<env_id>.json`, atomic write helper |
| Nginx route | `platform/lib/nginx_render.sh` -> `nginx/conf.d/<env_id>.conf` |
| print URL and TTL | final `printf` in create script |
| `destroy_env.sh` teardown | `platform/destroy_env.sh` |
| remove labeled containers | `docker ps -aq --filter label=sandbox.env=<env_id>` |
| archive logs | `logs/archived/<env_id>/<UTC ts>/` |
| cleanup daemon every 60s | `platform/cleanup_daemon.sh` |
| timestamped cleanup log | `logs/cleanup.log` via `log` helper |
| Nginx front door | `nginx/nginx.conf`, Compose service `nginx` |
| reload on create/delete | `write_conf` and `delete_conf` call `reload_nginx` |
| log shipping | `docker logs -f` PID stored in `bg_pids.log_shipper` |
| `make logs` | Makefile target tails `logs/<env_id>/app.log` |
| health poll every 30s | `monitor/health_poller.py` |
| degraded after 3 fails | monitor failure counter and atomic state update |
| outage modes | `platform/simulate_outage.sh` |
| never target Nginx/daemon | label assertion plus API precheck |
| API endpoints | `platform/api.py`, `/api/v1/...` |
| Makefile targets | `Makefile` |
| README docs | `README.md` |
| common mistakes avoided | atomic state, parameterized names, Nginx reload, PID cleanup |

## Debugging Playbook

Platform will not start:

```bash
make preflight
docker compose ps
docker compose logs sandbox-api
docker compose logs sandbox-nginx
```

Likely causes:

- `.env` mode is not `600`
- host port `18080` or `18081` already in use
- Docker daemon unavailable
- Nginx base config invalid
- not enough disk

Create fails:

```bash
bash platform/create_env.sh --name debug --ttl-minutes 5
docker ps -a --filter label=sandbox.env=<env_id>
docker network ls --filter label=sandbox.env=<env_id>
ls -la envs nginx/conf.d logs
```

Likely causes:

- invalid name or TTL
- demo image missing and build failed
- Nginx not running
- Nginx reload failed
- disk too low

Env URL returns 502:

```bash
docker exec sandbox-nginx nginx -t
docker inspect sandbox-nginx
docker network inspect sandboxnet-<env_id>
docker ps --filter name=sandbox-<env_id>-app
cat nginx/conf.d/<env_id>.conf
```

Likely causes:

- Nginx not connected to env network
- app container not running
- upstream name or app port mismatch
- stale/broken route config

Logs endpoint empty:

```bash
ls -la logs/<env_id>/
cat logs/<env_id>/app.log
cat envs/<env_id>.json
```

Likely causes:

- app has not logged yet
- log shipper PID died
- state file missing `bg_pids.log_shipper`

Health never degrades:

```bash
make simulate ENV=<env_id> MODE=crash
sleep 95
cat logs/<env_id>/health.log
cat envs/<env_id>.json
docker compose logs sandbox-monitor
```

Likely causes:

- not enough time for three 30-second polls
- monitor restarted and counter reset
- env status is `creating`, `destroying`, or `error`, so monitor skips it
- polling URL wrong

Destroy leaves resources:

```bash
docker ps -a --filter label=sandbox.env=<env_id>
docker network ls --filter label=sandbox.env=<env_id>
ls nginx/conf.d/<env_id>.conf
ps -ef | grep 'docker logs -f'
```

Likely causes:

- state missing before destroy, so fallback could not read network/PID
- Docker command failed
- process needed `KILL` after `TERM`
- Nginx reload failed after delete

## High-Probability Interview Questions

### 1. Why did you choose per-env Docker networks instead of host ports?

Because host ports do not scale cleanly and create collision problems. The brief
requires no hardcoded ports and everything parameterized by env ID. Per-env
Docker networks let every app listen on the same internal port while Nginx
routes by path. It also gives isolation: env A and env B are not on the same
network by default.

Follow-up:

> How does Nginx reach them?

Answer:

> Create connects `sandbox-nginx` to the new env network. Destroy disconnects
> it. Nginx becomes the only shared front door.

### 2. Why path-based routing instead of subdomains?

Because the assignment targets a single Linux VM and quick grading. Path-based
routing works with one IP and one host port without DNS automation or wildcard
TLS. It keeps the demo reproducible: `http://host:18080/<env_id>/health`.

### 3. How do you guarantee state is not corrupted?

State writes go through temp file plus fsync plus rename. Bash uses
`write_state_atomic` in `platform/lib/state.sh`; Python uses `os.replace` after
fsync. The daemon and API read JSON only after it has landed as a complete file.

### 4. What happens if create fails halfway?

`create_env.sh` has a rollback trap. It tracks which side effects have happened:
network created, container started, conf written, state written, log PID started.
On non-zero exit, it removes those resources, kills the log shipper if needed,
deletes generated Nginx config, removes logs, and either deletes or marks state.

### 5. Why use Bash for lifecycle instead of everything in FastAPI?

The assignment explicitly asks for `create_env.sh`, `destroy_env.sh`, and
`simulate_outage.sh`. Bash is a direct fit for Docker orchestration and Makefile
wrapping. FastAPI wraps those scripts so CLI and API behavior do not drift.

### 6. Why FastAPI?

It gives typed HTTP endpoints, automatic OpenAPI docs, simple middleware, and
clean JSON responses with less boilerplate than Flask for this control plane.
The actual orchestration remains in scripts.

### 7. How do you prevent outage simulation from killing Nginx?

The API only accepts an env ID and constructs the app container name from it.
Before the Bash script touches Docker, `assert_app_container` checks the Docker
label `sandbox.role`. If the target is not labelled `app`, it refuses. The API
also prechecks protected platform names and allowed modes.

### 8. What is your logging approach?

Approach A from the brief. On create, the script starts `docker logs -f` for the
app container and redirects output to `logs/<env_id>/app.log`. It stores the
background PID in `bg_pids.log_shipper` in state. Destroy terminates that PID
and archives the log directory.

### 9. What does "degraded" mean?

It means the health monitor has seen three consecutive failed polls for that env
through Nginx. A failure is a timeout, connection error, or non-2xx status. On a
later success, if the state was `degraded`, the monitor writes it back to
`running`.

### 10. What if a user creates the same name twice?

The implementation returns the existing active env for that name. That was the
idempotency decision: repeated create by name should not create duplicates.

### 11. How does auto-destroy work?

The daemon loops every 60 seconds. For every state file, it parses `created_at`
as UTC, adds `ttl_minutes`, and if current UTC time is later, calls the same
destroy script used by the CLI/API. That removes container, network, route,
logs, and state.

### 12. How do you know all resources are gone after destroy?

Destroy removes containers by Docker label, removes the known network, deletes
the generated route, kills background PIDs from state, archives logs, and
deletes state. To prove it, run Docker filters for `sandbox.env=<env_id>`, check
`docker network ls`, check `nginx/conf.d/<env_id>.conf`, and inspect
`logs/archived/<env_id>/`.

### 13. What is the weakest part of the design?

The Docker socket mount. It is powerful because the API can control Docker on
the host. The mitigation is narrow API endpoints, strict input validation, and
token enforcement when configured. In production I would put a smaller
privileged worker or policy-enforced Docker proxy between the API and Docker.

### 14. Why not Kubernetes?

The task explicitly required Docker, Docker Compose, Nginx, Bash/Makefile, and
Python on a single VM. Kubernetes would hide the low-level lifecycle mechanics
the task is testing. This implementation shows the mechanics directly.

### 15. How do you handle Nginx reload failures?

`write_conf` writes the snippet, then `reload_nginx` runs `nginx -t` before
reload. If validation fails, the generated conf is moved into `.broken` and the
create fails, triggering rollback.

### 16. How does the API handle long-running script calls?

For create, destroy, and recover, the API starts the script and waits a short
synchronous window. If the script completes, it returns the final result. If it
is still running, a background thread reaps the process and logs completion or
failure, while the API returns an accepted/pending style response.

### 17. How do you prove the API contract?

`make test-api` runs the Newman collection. The collection creates an env,
checks list/logs/health, triggers crash and recover, validates negative error
paths, destroys the env, then verifies the list returns to the baseline count.
CI runs this in the `build-test` job.

### 18. What is in the README quick start?

Five commands:

```bash
cp .env.example .env && chmod 600 .env
make up
make create NAME=demo TTL=5
curl http://localhost:18080/demo/health
make destroy ENV=<env-id-printed-by-create>
```

The README also notes that if `.env` is missing, `make up` creates it and exits
so the operator can review it.

### 19. What files are intentionally ignored by git?

Runtime logs, runtime state, `history.jsonl`, evidence bundles, generated
per-env Nginx configs, broken generated configs, `.env`, Python caches, editor
files, local archives, and prompt scratch files. `.env.example` and
`nginx/conf.d/.gitkeep` remain tracked.

### 20. What would you improve next?

Stage 6 improvements:

- replace file state with SQLite or Postgres
- persist monitor failure counters
- add active OPA evaluation before create/outage
- reduce Docker socket exposure with a policy proxy or worker
- add metrics with Prometheus/Grafana
- add per-env quotas and max active env enforcement at runtime
- add TLS and proper auth for a public deployment
- add log rotation for platform logs

## Follow-Up Trap Answers

If asked "Is this fully secure for untrusted users?":

> No. It is a single-VM sandbox suitable for the assignment and controlled
> demos. The Docker socket mount is not safe for arbitrary untrusted public use.
> The design mitigates with token auth, allowlisted endpoints, validation, and
> app container isolation, but production would need a stronger trust boundary.

If asked "Can two envs talk to each other?":

> Not by default. Each app is on its own network. Nginx is the shared component
> connected to each env network. The app containers are not attached to a common
> application network.

If asked "Does the API run OPA?":

> Not in the shipped runtime. The Rego policy files are present and document the
> policy shape. The actual enforcement is mirrored in Python prechecks and Bash
> label assertions.

If asked "Why does the API use `/api/v1/envs` when the brief says `/envs`?":

> The API is versioned under `/api/v1` to match the governance contract and to
> avoid colliding with env routes on Nginx. Nginx proxies `/api/v1/` to the API,
> while envs use `/<env_id>/` and `/<name>/`.

If asked "What happens after a VM reboot?":

> Compose can restart the platform containers, but any running dynamic app
> containers and background log shipper PIDs need reconciliation. The daemon can
> detect orphan containers and zombie state, but log shipper PID recovery is a
> limitation because PIDs are runtime-process specific. For production I would
> use a log driver or aggregator instead of background `docker logs -f`.

If asked "Why is the API token optional?":

> Local development needs low-friction startup, so blank token disables auth.
> The code path supports enforcement when `API_TOKEN` is set. For public server
> exposure, set a token and/or restrict firewall access.

If asked "How do you know no secrets are committed?":

> `.env` is ignored, `.env.example` carries only placeholders or blanks,
> `.dockerignore` excludes secrets from image builds, gitleaks runs in
> pre-commit and CI, and the custom gitleaks config catches `API_TOKEN` and
> long `*_KEY` literals.

If asked "What if Nginx is connected to too many networks?":

> On one VM and short TTLs, this is acceptable. The cleanup daemon and destroy
> path disconnect Nginx from networks. A larger version would enforce max active
> envs and maybe use a routing layer with service discovery instead of attaching
> one Nginx container to many networks.

If asked "Why not just route directly to container IPs?":

> Container IPs can change after restart. The generated config uses Docker DNS
> resolver and variable `proxy_pass` so Nginx resolves the container name through
> Docker DNS instead of pinning a stale IP.

If asked "How do you handle invalid JSON?":

> The API catches JSON decode errors and returns the unified error shape with
> `validation_error`. FastAPI request validation errors also go through the same
> error helper.

## Live Demo Drill

Use this sequence when asked to prove the system:

```bash
git status --short --branch
make up
docker compose ps
make create NAME=interview TTL=5
curl -fsS http://localhost:18080/interview/health
make health
make logs ENV=<env_id>
make simulate ENV=<env_id> MODE=crash
sleep 95
make health
make simulate ENV=<env_id> MODE=recover
sleep 35
make health
make destroy ENV=<env_id>
make test-api
make ship-check
```

What to say while running it:

1. `make up`: "This starts the platform control plane."
2. `make create`: "This creates the data-plane resources for one env."
3. `curl /health`: "This proves Nginx route plus app health."
4. `make logs`: "This proves log shipping by env ID."
5. `simulate crash`: "This breaks only the app container."
6. `sleep 95`: "The monitor needs three 30-second intervals."
7. `make health`: "Now state should show degraded."
8. `recover`: "Recover reverses the last outage."
9. `destroy`: "Destroy removes container, network, route, logs, and state."
10. `ship-check`: "This is the local release gate."

## Whiteboard From Memory

Draw this:

```text
                          +----------------------+
                          |      Docker Engine   |
                          +-----------+----------+
                                      ^
                                      |
                       docker socket  |
                                      |
+-------------+      /api/v1      +---+-----------+
|  Operator   +------------------> | sandbox-api   |
+-------------+                    +---+-----------+
                                      |
                                      | calls scripts
                                      v
                              platform/*.sh

+-------------+      :18080      +---------------+
|   User      +----------------> | sandbox-nginx |
+-------------+                  +-------+-------+
                                          |
                       connected to       |
                       sandboxnet-env-*   |
                                          v
                               +---------------------+
                               | sandbox-env-*-app   |
                               +---------------------+

+----------------+ reads envs/ +----------------+
| sandbox-daemon | ----------> | envs/*.json    |
+----------------+             +----------------+

+----------------+ polls Nginx +----------------+
| sandbox-monitor| ----------> | logs/*/health  |
+----------------+             +----------------+
```

Then annotate:

- state: `envs/<id>.json`
- logs: `logs/<id>/app.log`, `logs/<id>/health.log`
- routes: `nginx/conf.d/<id>.conf`
- history: `history.jsonl`

## Five-Minute Memory Drill

Answer each in one sentence:

1. What is the env ID format?
   - `env-` plus 8 lowercase hex characters.
2. What is the default TTL?
   - 30 minutes from `manifest.yaml` or `.env`.
3. What is the max TTL?
   - 240 minutes by default.
4. What port is ingress?
   - 18080.
5. What port is the API?
   - 18081 direct, also proxied through Nginx at `/api/v1/`.
6. What is the app port?
   - 5000 inside the demo container.
7. What marks a container as a sandbox app?
   - Docker label `sandbox.role=app`.
8. What labels identify ownership?
   - `sandbox.env=<env_id>`, `sandbox.role=app`, `sandbox.created_at=<UTC>`.
9. Where is state?
   - `envs/<env_id>.json`.
10. Where are app logs?
    - `logs/<env_id>/app.log`.
11. Where are health logs?
    - `logs/<env_id>/health.log`.
12. Where are archived logs?
    - `logs/archived/<env_id>/<UTC timestamp>/`.
13. What makes state writes safe?
    - temp file, JSON validation, fsync, rename.
14. What reloads Nginx?
    - `platform/lib/nginx_render.sh`.
15. What catches expired envs?
    - `platform/cleanup_daemon.sh`.
16. How often does cleanup run?
    - every 60 seconds by default.
17. How often does health polling run?
    - every 30 seconds by default.
18. When does status become degraded?
    - after three consecutive failed health polls.
19. What runs API contract tests?
    - Newman via `make test-api`.
20. What is the release gate?
    - `make ship-check`.

## If You Freeze

Use this fallback structure:

1. Name the component.
2. Name the file.
3. State the input.
4. State the side effects.
5. State the safety guard.
6. State how it is verified.

Example:

> Create is in `platform/create_env.sh`. Its input is name and TTL. It creates a
> Docker network, app container, Nginx route, log shipper, and state file. Its
> safety guards are validation, rollback trap, resource labels, and atomic state
> writes. It is verified by `make create`, `curl /health`, Postman, and
> `make ship-check`.

## Final Interview Positioning

The strongest stance is:

> I built the platform around explicit reversible side effects. Every create
> side effect has a matching destroy side effect: network create/remove,
> container run/remove, Nginx conf write/delete, reload/reload, log shipper
> start/kill, state write/delete, logs live/archive. The platform is simple
> because it is a single-VM assignment, but the important operational properties
> are present: parameterization, idempotency, atomic state, health monitoring,
> cleanup, guarded failure injection, CI, and documented limitations.
