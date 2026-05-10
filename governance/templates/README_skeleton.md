# devops-sandbox

> Self-service mini-Heroku with chaos engineering toggle. Spin up isolated, short-lived environments, deploy a demo app into each, simulate outages, monitor health, and tear it all down — automatically or on demand.

**HNG14 DevOps Stage 5** · Author: _<your-name>_ · Demo video: _<drive-link>_

---

## Table of Contents

1. [Architecture](#architecture)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Full Demo Walkthrough](#full-demo-walkthrough)
5. [Make Targets](#make-targets)
6. [API Reference](#api-reference)
7. [Network Approach](#network-approach)
8. [Log Shipping Approach](#log-shipping-approach)
9. [Configuration](#configuration)
10. [Project Layout](#project-layout)
11. [Known Limitations](#known-limitations)
12. [Troubleshooting](#troubleshooting)

---

## Architecture

```
<paste contents of governance/templates/ARCHITECTURE_DIAGRAM.txt here,
fenced as a code block so it renders monospaced>
```

**Components:**

- **Nginx (`sandbox-nginx`)** — single front door on host port `18080`. Routes `/<env-name>/` to the matching per-env container by name.
- **Control API (`sandbox-api`)** — FastAPI service on host port `18081`. Wraps `create_env.sh` / `destroy_env.sh` / `simulate_outage.sh`.
- **Cleanup daemon (`sandbox-daemon`)** — runs `cleanup_daemon.sh` on a 60s loop, destroys expired envs.
- **Health monitor (`sandbox-monitor`)** — `health_poller.py` polls each env's `/health` every 30s; flips status to `degraded` after 3 consecutive failures.
- **Per-env app container (`sandbox-<env_id>-app`)** — the user's demo app, isolated on its own Docker network `sandboxnet-<env_id>`, joined to the platform network only via Nginx.

---

## Prerequisites

- Linux VM (tested on Ubuntu 22.04+) — _everything must run on a single Linux VM_
- Docker Engine ≥ 24.x
- Docker Compose v2 (the `docker compose` plugin, not the legacy `docker-compose`)
- GNU Make
- Bash 4+
- Python 3.11+ (for local linting/dev only — the API and monitor run inside containers)
- ~2 GB free disk, ~1 GB free RAM headroom

> **Required user permission:** the user running `make up` must be in the `docker` group, OR `make` must be run with `sudo`.

---

## Quick Start

Zero to first running env in **5 commands**:

```bash
# 1. Clone
git clone https://github.com/<you>/devops-sandbox.git && cd devops-sandbox

# 2. Configure
cp .env.example .env   # then edit API_TOKEN if you want auth on

# 3. Boot the platform
make up

# 4. Create your first env (prompts for name + TTL)
make create

# 5. Open it
curl http://localhost:18080/<the-name-you-just-typed>/
```

---

## Full Demo Walkthrough

This is the script the demo video follows. Every step is a single make target — no manual `docker run` invocations.

```bash
# 0. Start the platform
make up

# 1. Create a sandbox env named "demo" with a 5-minute TTL
make create     # type: demo, then 5

# 2. Hit the deployed app through Nginx
curl http://localhost:18080/demo/
curl http://localhost:18080/demo/health

# 3. Inspect health history
make health

# 4. Tail recent app logs
make logs ENV=env-<the-id-printed-by-step-1>

# 5. Simulate a crash → watch the monitor flip status to degraded within ~90s
make simulate ENV=env-<id> MODE=crash
sleep 95
make health     # should now show: degraded

# 6. Recover
make simulate ENV=env-<id> MODE=recover
sleep 35
make health     # back to: running

# 7. Wait for TTL to expire → daemon auto-destroys (or destroy manually)
make destroy ENV=env-<id>

# 8. Tear down the platform and wipe state
make down
make clean
```

---

## Make Targets

| Target                     | Purpose                                                    |
|----------------------------|------------------------------------------------------------|
| `make up`                  | Start Nginx + daemon + API + monitor                       |
| `make down`                | Stop everything; destroy every active env first            |
| `make create`              | Prompt for `name` + `TTL`, then create a sandbox env       |
| `make destroy ENV=<id>`    | Destroy a single env by ID                                 |
| `make logs ENV=<id>`       | Tail `logs/<id>/app.log` (last 100 lines, then follow)     |
| `make health`              | Print health status of every active env                    |
| `make simulate ENV=<id> MODE=<mode>` | Run an outage simulation (`crash`/`pause`/`network`/`recover`/`stress`) |
| `make clean`               | Wipe all state, logs, and archives — irrecoverable         |
| `make test-api`            | Run the Postman collection via Newman against the live API |

---

## API Reference

Base URL: `http://localhost:18081/api/v1`

See [`docs/API.md`](docs/API.md) for the full contract. Quick reference:

| Method | Path                       | Purpose                              |
|--------|----------------------------|--------------------------------------|
| POST   | `/envs`                    | Create env                           |
| GET    | `/envs`                    | List active envs + TTL remaining     |
| DELETE | `/envs/{id}`               | Destroy env                          |
| GET    | `/envs/{id}/logs`          | Last 100 lines of `app.log`          |
| GET    | `/envs/{id}/health`        | Last 10 health-check results         |
| POST   | `/envs/{id}/outage`        | Trigger outage simulation            |

Auth (optional): `X-API-Token: <value of API_TOKEN in .env>`. If `API_TOKEN` is unset, the API runs open.

---

## Network Approach

Every env gets its own Docker bridge network: `sandboxnet-<env_id>`. The app container is **only** on that per-env network — it cannot see other envs, the daemon, the monitor, or the API.

The Nginx container is multi-homed: it sits on `sandboxnet-platform` (where it talks to the API) and is **dynamically joined** to each `sandboxnet-<env_id>` at create-time via `docker network connect`, then disconnected at destroy-time. This is what lets one Nginx process route to N isolated envs without putting everything on one flat network.

The control API also mounts `/var/run/docker.sock` (read-write) so it can shell out to `docker` and the lifecycle scripts. Risks and mitigations are documented in `docs/THREAT_MODEL.md`.

---

## Log Shipping Approach

**Approach A (chosen).** When `create_env.sh` starts the app container, it forks `docker logs -f <container_id> >> logs/<env_id>/app.log` as a background process and stores its PID in the state file's `bg_pids.log_shipper` field. `destroy_env.sh` reads that PID, sends `SIGTERM`, waits up to 5s, then `SIGKILL` if needed — preventing zombie processes (Pitfall #3 from the brief).

The trade-off vs Approach B (Loki/Fluentd): less resilient to API restarts, but zero extra containers and zero extra ports. Acceptable for a stage 5 sandbox.

---

## Configuration

All config lives in `.env` (gitignored). See `.env.example` for the full list. Highlights:

| Variable           | Default       | Purpose                                          |
|--------------------|---------------|--------------------------------------------------|
| `API_TOKEN`        | _unset_       | If set, required as `X-API-Token` on every call  |
| `DEFAULT_TTL_MIN`  | `30`          | TTL when caller doesn't specify                  |
| `MAX_TTL_MIN`      | `240`         | Hard ceiling                                     |
| `INGRESS_PORT`     | `18080`       | Public Nginx port on the host                    |
| `API_PORT`         | `18081`       | Control API port on the host                     |
| `HEALTH_INTERVAL_S`| `30`          | Health poll cadence                              |
| `CLEANUP_INTERVAL_S`| `60`         | Daemon loop cadence                              |

---

## Project Layout

```
devops-sandbox/
├── platform/
│   ├── create_env.sh
│   ├── destroy_env.sh
│   ├── cleanup_daemon.sh
│   ├── simulate_outage.sh
│   ├── api.py
│   └── lib/             # shared bash helpers (atomic_write, log_event, …)
├── nginx/
│   ├── nginx.conf
│   └── conf.d/          # per-env <env_id>.conf — auto-generated, gitignored
├── monitor/
│   └── health_poller.py
├── demo-app/            # the throwaway Flask "Hello World" deployed into each env
│   ├── Dockerfile
│   └── app.py
├── docs/
│   ├── API.md
│   └── THREAT_MODEL.md
├── journal/             # live journal entries — feed into the blog post
├── policies/            # OPA Rego policies
├── postman/
├── logs/                # gitignored
├── envs/                # runtime state files — gitignored
├── docker-compose.yml
├── Makefile
├── .env.example
├── .gitignore
└── README.md
```

---

## Known Limitations

- Single-VM only; no clustering. Nginx, the daemon, the API, and every env share one host.
- TTLs use wall-clock UTC; if the system clock jumps backwards, premature destruction is possible (acceptable trade-off — see journal entry on this).
- No persistent volumes inside envs; redeploy = data loss. By design — these are sandboxes.
- API auth is a single shared token. No per-user identity, no RBAC. Adequate for a sandbox; would not be in production.
- Demo app is a stub. Swap it for your own image by editing `demo-app/Dockerfile`.

---

## Troubleshooting

**`make up` fails with "permission denied" on `/var/run/docker.sock`.**
Add your user to the `docker` group: `sudo usermod -aG docker $USER`, then log out and back in.

**Nginx returns 502 a few seconds after `make create`.**
The app container is still booting. Wait ~5s and retry. Nginx itself is fine.

**Env stuck in `degraded` after `recover`.**
The monitor needs one successful poll to clear the failure counter. Wait ~35s and re-check `make health`.

**`make destroy` says "env not found" but state file exists.**
You probably edited `envs/<id>.json` by hand. Don't — run `destroy_env.sh` directly with `--force` to clean up.

---

_Built for HNG14 DevOps Stage 5. Governance pack: see `governance/`. Live build journal: see `journal/`._
