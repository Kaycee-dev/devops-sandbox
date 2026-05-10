# 02 — Sprint Plan

Six sprints. The deadline is **12 May 2026, 14:30 WAT**. Today is **9 May 2026**. That is roughly 72 hours of wall clock, of which maybe 20–25 hours of focused work after sleep, meals, and life. The sprints are sized to that budget.

Each sprint has an entry condition (what must already exist), an exit condition (what proves the sprint is closed), and a recommended hour budget. The exit condition is a **green gate**, not a feeling.

---

## Sprint 0 — Bootstrap (1.5 hours)

**Goal**: Empty repo → governance pack copied in → CI scaffolding live → first journal entry committed.

**Entry**: Empty `devops-sandbox` repo on disk; this governance pack available.

**Tasks**
1. `git init`, push empty repo to GitHub as `Kaycee-dev/devops-sandbox`.
2. Copy `governance/` into the repo root (this whole pack).
3. Write `.gitignore`, `.dockerignore`, `.gitattributes` (mirror Stage 4A's).
4. Symlink (or copy) `governance/ci/pre-commit-config.yaml` → `.pre-commit-config.yaml` and same for gitleaks.
5. Run `pre-commit install`. Confirm hooks fire on a dummy commit.
6. Write the first journal entry: `journal/2026-05-09-01-bootstrap.md`. Use the template. Plan section: "Sprint 0 — bootstrap." Outcomes section: "all hooks green on empty repo."

**Exit**:
- `pre-commit run --all-files` exits 0 on the empty-but-scaffolded repo.
- `gitleaks detect` exits 0.
- One journal entry committed.
- README skeleton present (from `templates/README_skeleton.md`).

---

## Sprint 1 — Skeleton + manifest + demo app (3 hours)

**Goal**: `manifest.yaml` exists. `docker-compose.yml` is rendered from it (or hand-written, decision logged). The demo Flask app builds and serves `/` and `/health`. Nginx container starts and serves a static landing page.

**Tasks**
1. Write `manifest.yaml` per `01_CONSTITUTION.md` §1.2. Include: `defaults.ttl_minutes: 30`, `defaults.image: sandbox-demo:1.0.0`, `network.public_port: 18080`, `resources.cpus: 1.0`, `resources.memory_mb: 512`, port allocation strategy.
2. Write `demo-app/`: minimal Flask app with `/` returning 200 + env-id header echo, and `/health` returning 200 + JSON `{"status":"ok"}`. Multi-stage Dockerfile, non-root user.
3. Write `nginx/nginx.conf`: top-level config that includes `conf.d/*.conf` and serves a 200 OK landing page on `/` of the public port.
4. Write `docker-compose.yml`: services `nginx`, `api`, `daemon`, `monitor`. `api` and `daemon` and `monitor` are stubs that just `sleep infinity` for now.
5. `make up` works. `make down` works. Both idempotent.
6. Journal entry. Teach-back blocks for: ID format choice, port-allocation strategy, why we ship a demo app at all (the brief says we don't have to, but we want a known-good payload for testing).

**Exit**:
- `make up && curl -fsSL localhost:18080/ | grep -q 'sandbox'` passes.
- `docker compose ps` shows 4 platform services healthy.
- `nginx -t` passes inside the container.

---

## Sprint 2 — Lifecycle scripts (4 hours)

**Goal**: `create_env.sh` and `destroy_env.sh` work end-to-end from the CLI. State is atomic. Nginx routes are dynamic. Idempotency holds.

**Tasks**
1. `platform/lib/state.sh`: `write_state_atomic`, `read_state`, `delete_state`, `assert_app_container`.
2. `platform/lib/env_id.sh`: ID gen (`env-` + 8 hex chars), validation regex, lookup by name.
3. `platform/lib/nginx_render.sh`: `write_conf $ENV_ID $UPSTREAM`, `delete_conf $ENV_ID`, `reload_nginx` with `-t` gate.
4. `platform/lib/logging.sh`: `log $LEVEL $COMPONENT $ENV_ID $MSG`.
5. `platform/create_env.sh`: parse `--name`, `--ttl-minutes`, generate ID, create network `sandboxnet-$ENV_ID`, run app container with labels and resource caps, write state, write Nginx conf, reload, print URL + TTL.
6. `platform/destroy_env.sh`: read state, kill `bg_pids`, stop+rm container, rm network, delete Nginx conf + reload, archive logs to `logs/archived/$ENV_ID/`, delete state.
7. Append events to `history.jsonl` on every create/destroy.
8. Journal entry with teach-backs on: atomic write pattern (the headline pitfall), label schema, log archival format.

**Exit**:
- `bash platform/create_env.sh --name demo --ttl-minutes 5` returns a URL that responds 200 within 10 seconds.
- `bash platform/destroy_env.sh <id>` removes container, network, conf, state. `docker ps -a | grep sandbox-$ENV_ID` returns nothing.
- Running `create_env.sh` twice with the same name behaves per the documented decision (allow-reuse or refuse).
- Running `destroy_env.sh missing-id` exits 0.
- A `bats` test asserting atomicity (kill -9 mid-write, state file is intact-or-absent, never half-written) passes.

---

## Sprint 3 — Daemon, monitor, log shipping (3 hours)

**Goal**: Auto-cleanup runs every 60s. Health poller runs every 30s. Logs are shipped per chosen approach. `degraded` flips after 3 fails.

**Tasks**
1. `platform/cleanup_daemon.sh`: 60s loop, signal-trapped, atomic state reads, calls `destroy_env.sh` on TTL miss, writes `logs/cleanup.log`. Started under `nohup` from compose.
2. `monitor/health_poller.py`: reads `envs/*.json`, hits each env's `/health` every 30s with a 5s timeout, writes `logs/$ENV_ID/health.log` with `<ts> <status> <latency_ms>`. Maintains an in-memory consecutive-fail counter; on the 3rd consecutive fail, calls `update_status $ENV_ID degraded` and emits a warning log.
3. Choose log shipping approach. Document in journal AND in README. Default: Approach A (`docker logs -f` redirect with PID stored in state). PID killed on destroy per §6.2.
4. `make logs ENV=…` tails `logs/$ENV_ID/app.log`. `make health` prints status of every env from `envs/*.json`.
5. Journal entry with teach-backs on: 30s vs 60s cadence, why "3 consecutive" not "3 of last 5", Approach A vs B trade-off.

**Exit**:
- An env with `--ttl-minutes 1` is auto-destroyed within 60–120s of TTL expiry; `logs/cleanup.log` shows the action.
- An env whose container is `docker kill`'d is flipped to `degraded` within 90s; the `degraded` flip is in `history.jsonl`.
- `make logs ENV=<id>` prints non-empty output for a running env.

---

## Sprint 4 — Outage simulation + control API (4 hours)

**Goal**: `simulate_outage.sh` works for all 4 modes (+stress optional). Sandbox guard refuses to act on platform containers. FastAPI control plane exposes the 6 endpoints. Postman pack passes.

**Tasks**
1. `platform/simulate_outage.sh --env --mode {crash|pause|network|recover|stress}`. First action: `assert_app_container`. Each mode is a one-liner wrapping the right `docker` command. `recover` interrogates the env's last-known outage mode (from `history.jsonl`) and reverses it.
2. `platform/api.py` (FastAPI): 6 endpoints per `10_API_CONTRACT.md`. Internally shells out to `create_env.sh`, `destroy_env.sh`, `simulate_outage.sh`. Reads state files for list/health/logs. Optional `X-API-Token` header check if `API_TOKEN` set in `.env`.
3. Wire `api` service in `docker-compose.yml` with the docker socket mounted (`/var/run/docker.sock:/var/run/docker.sock`) so the API can shell-exec the lifecycle scripts that need Docker.
4. `make test-api` runs Newman against the local stack.
5. Journal entry with teach-backs on: docker-socket mount risk and mitigation, why FastAPI over Flask, idempotency-key handling on POST /envs.

**Exit**:
- Postman pack: 100% passing on local stack.
- `simulate_outage.sh --env <id> --mode crash` causes a `degraded` flip within 90s.
- `simulate_outage.sh --env sandbox-nginx` (platform container) exits 2 with the refusal message.
- API responds to all 6 endpoints with the documented shape.

---

## Sprint 5 — Polish, README, demo, ship-check (2.5 hours)

**Goal**: Everything in the README. Demo evidence captured. `make ship-check` green. Video recorded.

**Tasks**
1. README: render from `templates/README_skeleton.md`. Architecture diagram (ASCII first, optional PNG later). Prerequisites, quick-start in ≤5 commands, full demo walkthrough, known limitations.
2. `scripts/capture_evidence.sh`: runs the full demo (create → check health → simulate crash → observe degraded → recover → wait for auto-destroy), saves logs and timestamped screenshots to `evidence/<ts>/`. The video voiceover follows the same beats; see `08_DEMO_SCRIPT.md`.
3. Optional: Prometheus + Grafana sidecar. `metrics_total`, `envs_active`, `health_failures_total`, `outages_triggered_total`. Only if Sprints 0–4 are green and time remains.
4. `make ship-check` implementation. Runs every gate. Exits 0 only if every gate passes.
5. Record the 3-minute video. Beats per `08_DEMO_SCRIPT.md`. Upload to Drive. Share link.
6. Final journal entry: "Sprint 5 — ship". List unfinished items as known limitations.

**Exit**:
- `make ship-check` exits 0.
- README's quick-start, copy-pasted into a fresh shell on the same VM, takes a reviewer from zero to a running env in ≤5 commands.
- Video recorded, uploaded, link in README.

---

## Hour budget summary

| Sprint | Budget | Cumulative |
|--------|--------|------------|
| 0 — Bootstrap | 1.5h | 1.5h |
| 1 — Skeleton + demo app | 3h | 4.5h |
| 2 — Lifecycle | 4h | 8.5h |
| 3 — Daemon + monitor + logs | 3h | 11.5h |
| 4 — Outage + API | 4h | 15.5h |
| 5 — Polish + ship | 2.5h | 18h |
| **slack/blockers buffer** | 6h | 24h |

Total: ~24 hours of focused work. If actual hours blow past 30, stop the sprint plan and write an honest "what is and is not shippable by the deadline" assessment in the journal. Cut the optional Prometheus/Grafana pieces first, then the OPA policies, then anything else, in that order. Never cut acceptance criteria.

## Daily checkpoint ritual

End of each day, run `make ship-check`, paste output into the journal entry, and note exactly which acceptance rows are now ☑. If `ship-check` is failing, the morning's first task is to make it pass before starting new work.
