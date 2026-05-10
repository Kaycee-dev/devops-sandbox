# 06 — Definition of Done

A component is "done" only when every line of its DoD list is checked. The agent ticks these in the journal entry that closed the component. "Mostly done" is not done.

## Per-component DoD

### `create_env.sh`

- [ ] Accepts `--name <str>` and optional `--ttl-minutes <int>`.
- [ ] Generates an env ID matching `^env-[0-9a-f]{8}$`.
- [ ] Creates a Docker network named `sandboxnet-${ENV_ID}`.
- [ ] Starts the demo-app container with all required labels (§3.3) and resource caps (§12.1).
- [ ] Stores the log-shipping PID (Approach A) or aggregator config ID (Approach B) in the state file.
- [ ] Writes state via the atomic helper from `lib/state.sh`.
- [ ] Writes Nginx conf via the helper, runs `nginx -t`, then reloads.
- [ ] Appends a `created` event to `history.jsonl`.
- [ ] Prints `URL: http://<host>:<port>/<env-id>` and `TTL: <minutes>` on success.
- [ ] On any failure mid-create, rolls back partial state (network, container, conf, PID file).
- [ ] Exits 0 on success, non-zero with a clear message on failure.
- [ ] Idempotency behaviour matches the journaled decision (allow-reuse-by-name OR refuse with a clear error).
- [ ] `bats` test suite covers happy path, name-collision, low-disk refusal, mid-create rollback.

### `destroy_env.sh`

- [ ] Accepts an env ID positional argument.
- [ ] Reads state; if missing, exits 0 with a "not found, nothing to do" log line.
- [ ] Kills every PID in `bg_pids` and waits for each.
- [ ] Stops and removes every container labelled `sandbox.env=$ENV_ID`.
- [ ] Removes the Docker network.
- [ ] Deletes `nginx/conf.d/${ENV_ID}.conf` and reloads Nginx (with `-t` gate).
- [ ] Archives `logs/$ENV_ID/` to `logs/archived/$ENV_ID/<UTC ts>/` (preserves contents, doesn't move-and-clobber).
- [ ] Deletes the state file.
- [ ] Appends a `destroyed` event to `history.jsonl`.
- [ ] `bats` test suite covers happy path, missing-id (exit 0), already-destroyed (exit 0), zombie-PID detection.

### `cleanup_daemon.sh`

- [ ] Loops every 60 seconds.
- [ ] On each tick, lists `envs/*.json`, parses `created_at` and `ttl`, and computes `expired = now > created_at + ttl`.
- [ ] For expired envs, calls `destroy_env.sh $ENV_ID`.
- [ ] Logs every action with `<UTC ts> <level> cleanup_daemon $ENV_ID <message>` to `logs/cleanup.log`.
- [ ] Traps SIGTERM and SIGINT; logs `daemon stopped` on exit; never exits silently.
- [ ] Reconciles orphans: container exists but no state file → destroy container; state file exists but no container → mark `error` and warn.
- [ ] Runs under `nohup` (or compose-managed equivalent) so terminal close doesn't kill it.
- [ ] `bats` test suite covers TTL expiry, signal handling, orphan reconciliation.

### `simulate_outage.sh`

- [ ] Accepts `--env <id>` and `--mode {crash|pause|network|recover|stress}`.
- [ ] **First action**: `assert_app_container` — exits 2 with refusal message if target's `sandbox.role != app`.
- [ ] `crash` → `docker kill`. `pause` → `docker pause`. `network` → `docker network disconnect`.
- [ ] `recover` → reads last outage event from `history.jsonl` for this env and reverses it.
- [ ] `stress` (optional) → `stress-ng --cpu N --timeout 30s` inside the container.
- [ ] Appends `outage` event to `history.jsonl` with `mode`, `triggered_by`, `restored_by` (for recover).
- [ ] `bats` test suite covers refusal, every mode, recover-without-prior-outage (exits 0 with "nothing to recover").

### `health_poller.py`

- [ ] Reads `envs/*.json` at the top of each tick.
- [ ] Hits `<env_url>/health` with a 5s timeout.
- [ ] Writes `<UTC ts> <http_status> <latency_ms>` to `logs/$ENV_ID/health.log`.
- [ ] Maintains an in-memory consecutive-failure counter per env.
- [ ] After 3 consecutive failures, calls a state helper to set the env's status to `degraded` and emits a stderr warning.
- [ ] Resets the counter on first success after a failure run.
- [ ] Sleeps 30 seconds between ticks (configurable via env var `HEALTH_INTERVAL_SECONDS`).
- [ ] Survives transient errors (network blip, env mid-create) without crashing.
- [ ] Unit tests cover counter logic, log format, status flip.

### `api.py` (FastAPI)

- [ ] Implements all six endpoints per `10_API_CONTRACT.md`, with the documented request/response shapes.
- [ ] Wraps the four bash scripts via `subprocess.run`, with a strict timeout and `text=True`.
- [ ] All errors return the unified shape `{ "error": { "code": "<machine_code>", "message": "<human>" } }`.
- [ ] Optional `X-API-Token` enforcement when `API_TOKEN` is set in `.env`.
- [ ] Structured access logging to `logs/api.log`.
- [ ] OpenAPI schema served at `/docs` (FastAPI default; do not disable).
- [ ] Postman pack passes against the running API.
- [ ] Unit tests cover argument validation, subprocess error handling, token enforcement.

### `nginx/`

- [ ] `nginx.conf` is the only file in nginx/ outside `conf.d/`.
- [ ] `nginx.conf` includes `conf.d/*.conf`.
- [ ] `conf.d/.gitkeep` exists; no per-env confs are committed.
- [ ] Each per-env conf is a single `server { }` block with `server_name`, `listen`, `location /`, `proxy_pass http://sandbox-${ENV_ID}-app:<port>`.
- [ ] `nginx -t` runs as a gate before every reload.

### `Makefile`

- [ ] All 8 targets from the brief are implemented and behave per the spec.
- [ ] Plus: `test-api`, `ship-check`, `bundle-evidence`, `lint`, `format`.
- [ ] `make help` (the default target) prints a description of each target with one-line summaries.
- [ ] Every target prints a usage line if called with missing required vars (e.g. `make destroy` without `ENV=…`).
- [ ] `.PHONY` declared for every non-file target.

### `README.md`

- [ ] Title, one-paragraph elevator pitch.
- [ ] Architecture diagram (ASCII; PNG optional).
- [ ] Prerequisites list (Docker version, Compose v2, free disk, free port).
- [ ] Quick-start section: ≤ 5 commands from clone to running env.
- [ ] Demo walkthrough: create → check health → simulate crash → observe degraded → recover → wait for auto-destroy. Each step shows the exact command and the exact expected output.
- [ ] Logging approach documented (Approach A or B, with reasoning).
- [ ] Network approach documented (per-env Docker network strategy and how Nginx reaches the upstreams).
- [ ] Known limitations.
- [ ] Link to the 3-minute walkthrough video.
- [ ] Changelog (auto-generated or hand-curated, links to journal entries).

## Overall ship-readiness DoD

- [ ] Every row in `03_ACCEPTANCE_CRITERIA.md` Sections A and B is ☑.
- [ ] `make ship-check` exits 0 on a freshly cloned repo, with `.env` filled from `.env.example`.
- [ ] Newman pack: 100% pass against the deployed server.
- [ ] gitleaks: 0 findings on full history.
- [ ] shellcheck: 0 errors on every `.sh` file.
- [ ] Every journal entry has the mandatory sections; the union of `acceptance_rows_closed` = the set of ☑ rows.
- [ ] README quick-start reproduces on a fresh Linux VM.
- [ ] Video uploaded; link in README; link tested in private-browsing mode.
- [ ] Submission form filled and submitted.

The DoD is a checklist, not a vibe. The agent ticks the boxes in the journal; the human verifies they are honestly ticked.
