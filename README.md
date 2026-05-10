# devops-sandbox

Self-service DevOps sandbox platform for HNG14 Stage 5: create short-lived isolated Docker environments, route them through Nginx, stream logs by env ID, poll health, simulate outages, recover, and destroy everything manually or by TTL.

Demo video: **pending Kelechi upload**
Live server: **pending VM deployment**

## Architecture

```text
             host ports
        18080        18081
          |            |
          v            v
   +--------------+  +----------------+
   | sandbox-nginx|  |  sandbox-api   |
   | front door   |  | FastAPI wrapper|
   +------+-------+  +--------+-------+
          |                   |
          | joins per-env     | shells out to platform/*.sh
          | networks          |
          v                   v
 +-------------------+   +------------------+
 | sandboxnet-env-*  |   | Docker Engine    |
 | sandbox-*-app     |   | containers/nets  |
 +-------------------+   +------------------+
          ^
          |
 +--------+---------+     +-----------------+
 | sandbox-monitor  |     | sandbox-daemon  |
 | /health poller   |     | TTL cleanup     |
 +------------------+     +-----------------+
```

Nginx is the public front door on `http://localhost:18080`. The API is also exposed directly on `http://localhost:18081/api/v1` and proxied at `http://localhost:18080/api/v1`.

## Prerequisites

- Linux VM or WSL2 with Docker Engine access
- Docker Engine 24+ and Docker Compose v2
- GNU Make and Bash
- Python 3 for local helper checks
- At least 2 GiB free disk
- Host ports `18080` and `18081` free

## Quick Start

From a fresh clone to a running env:

```bash
cp .env.example .env && chmod 600 .env
make up
make create NAME=demo TTL=5
curl http://localhost:18080/demo/health
make destroy ENV=<env-id-printed-by-create>
```

If `.env` is missing, `make up` creates it from `.env.example`, fixes mode to `600`, and exits so you can review it before booting.

## Demo Walkthrough

```bash
make up
make create NAME=demo TTL=5
curl http://localhost:18080/demo/
curl http://localhost:18080/demo/health
make health
make logs ENV=<env-id>
make simulate ENV=<env-id> MODE=crash
sleep 95
make health
make simulate ENV=<env-id> MODE=recover
make destroy ENV=<env-id>
make down
make clean
```

The API version of the same flow is covered by:

```bash
make test-api
```

The current Postman gate passes locally: 14 requests, 59 assertions, 0 failures.

## Make Targets

| Target | Purpose |
|---|---|
| `make up` | Preflight, build images, start Nginx, API, daemon, monitor |
| `make down` | Destroy active envs where possible and stop platform containers |
| `make create NAME=demo TTL=5` | Create or return an existing env by name |
| `make destroy ENV=env-abc12345` | Destroy one env |
| `make logs ENV=env-abc12345` | Tail `logs/<env>/app.log` |
| `make health` | Print active env status |
| `make simulate ENV=... MODE=crash` | Run outage simulation |
| `make clean` | Remove runtime state/logs/generated env configs |
| `make test-api` | Run the Postman collection with Newman |
| `make ship-check` | Run local aggregate checks |

## API

Base URL: `http://localhost:18081/api/v1`

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/envs` | Create env |
| `GET` | `/envs` | List envs with TTL remaining |
| `DELETE` | `/envs/{id}` | Destroy env |
| `GET` | `/envs/{id}/logs` | Last 100 app log lines |
| `GET` | `/envs/{id}/health` | Last 10 health checks |
| `POST` | `/envs/{id}/outage` | `crash`, `pause`, `network`, `recover`, `stress` |

If `API_TOKEN` is set in `.env`, requests must include `X-API-Token: <token>`. Local development can leave it blank.

## Network Approach

Each environment gets a dedicated Docker bridge network named `sandboxnet-<env_id>`. The app container is named `sandbox-<env_id>-app` and does not bind host ports. `sandbox-nginx` is connected to each env network at create time and disconnected on destroy.

Generated route files live at `nginx/conf.d/<env_id>.conf`. They are path-based snippets included inside the main Nginx server so both URLs work:

- `http://localhost:18080/<env_id>/`
- `http://localhost:18080/<name>/`

Every write/delete of a generated Nginx route runs `docker exec sandbox-nginx nginx -t` before reload.

## Log Shipping

Approach A is implemented. `create_env.sh` starts:

```bash
nohup docker logs -f <container_id> >> logs/<env_id>/app.log 2>&1 &
```

The PID is stored in the state file as:

```json
{ "bg_pids": { "log_shipper": 12345 } }
```

`destroy_env.sh` terminates that PID before removing the container and archives logs under `logs/archived/<env_id>/<UTC timestamp>/`.

## State and Health

Runtime state lives in `envs/<env_id>.json` and is always written via temp file, `fsync`, and rename. The monitor polls each active env through Nginx every 30 seconds and appends:

```text
<UTC ISO timestamp> <http_status> <latency_ms>
```

After three consecutive failures, the monitor marks the env `degraded`.

## Known Limitations

- Single-host only; no clustering or remote Docker contexts.
- The API uses the Docker socket and runs with enough privilege to operate containers.
- OPA policy files are present, but the API mirrors their outage rules rather than requiring an `opa` binary.
- The demo video link and live VM URL are pending external upload/deployment.
- `stress` mode uses a short Python CPU loop inside the demo container, not `stress-ng`.

## Changelog

- `journal/2026-05-10-01-skeleton-and-demo-app.md`
- `journal/2026-05-10-02-lifecycle.md`
- `journal/2026-05-10-03-daemon-monitor.md`
- `journal/2026-05-10-04-api-outage.md`
- `journal/2026-05-10-05-polish-ship.md`
