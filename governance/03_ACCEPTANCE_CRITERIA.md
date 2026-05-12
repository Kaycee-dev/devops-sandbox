# 03 — Acceptance Criteria Matrix

Every row is one closeable requirement. A row is ☑ only when **all four** of `Code`, `Make`, `Postman/Test`, and `Journal` columns reference real, committed artifacts. Half-credit is forbidden — there is no ◐ glyph, on purpose.

The matrix is sectioned by source: **Explicit** rows come straight from `CURRENT_TASK`. **Implied** rows are obvious-once-stated requirements that the brief assumes without listing. **Quality** rows come from `01_CONSTITUTION.md` and `07_DEVSECOPS_GUARDRAILS.md`. The agent closes them in roughly that order; ship-check refuses to pass until every row is ☑ or explicitly waived in `09_KNOWN_PITFALLS.md`.

## Section A — Explicit requirements

| # | Requirement (verbatim or near-verbatim from `CURRENT_TASK`) | Code | Make target | Postman / test | Journal | ☑ |
|---|---|---|---|---|---|---|
| A01 | Repo named `devops-sandbox`, structure as listed | n/a (repo metadata) | — | — | journal/2026-05-09-01-bootstrap | ☑ |
| A02 | `create_env.sh` takes name and optional TTL (default 30 min) | `platform/create_env.sh` | `make create` | Postman: Create env | …02-lifecycle | ☑ |
| A03 | `create_env.sh` generates a unique env ID | `platform/lib/env_id.sh::new_env_id` | — | bats: `env_id.bats` uniqueness | …02-lifecycle | ☑ |
| A04 | `create_env.sh` creates a dedicated Docker network | `platform/create_env.sh` | — | Postman: Create env (asserts `network` field) | …02-lifecycle | ☑ |
| A05 | App container labelled `sandbox.env=$ENV_ID` | `platform/create_env.sh` | — | bats: `docker inspect` label | …02-lifecycle | ☑ |
| A06 | State file written to `envs/$ENV_ID.json` (id, name, created_at, ttl, status) | `platform/lib/state.sh::write_state_atomic` | — | bats: state schema | …02-lifecycle | ☑ |
| A07 | Nginx route registered on create | `platform/lib/nginx_render.sh::write_conf` | — | Postman: Create env (URL responds 200) | …02-lifecycle | ☑ |
| A08 | Print env URL and TTL on completion | `platform/create_env.sh` (final echo) | — | bats: stdout regex | …02-lifecycle | ☑ |
| A09 | `destroy_env.sh` stops/removes labeled containers | `platform/destroy_env.sh` | `make destroy` | Postman: Destroy env | …02-lifecycle | ☑ |
| A10 | `destroy_env.sh` removes the Docker network | `platform/destroy_env.sh` | — | bats: `docker network ls` empty | …02-lifecycle | ☑ |
| A11 | `destroy_env.sh` deletes Nginx config and reloads | `platform/destroy_env.sh` | — | bats: `conf.d/$ENV_ID.conf` absent + `nginx -t` ok | …02-lifecycle | ☑ |
| A12 | `destroy_env.sh` archives logs to `logs/archived/$ENV_ID/` | `platform/destroy_env.sh` | — | bats: directory exists post-destroy | …02-lifecycle | ☑ |
| A13 | `destroy_env.sh` deletes state file | `platform/destroy_env.sh` | — | bats: `envs/$ENV_ID.json` absent | …02-lifecycle | ☑ |
| A14 | `cleanup_daemon.sh` loops every 60 seconds | `platform/cleanup_daemon.sh` | — | journaled: time-stamped runs in `logs/cleanup.log` | …03-daemon | ☑ |
| A15 | Daemon checks `now > created_at + ttl` per env | `platform/cleanup_daemon.sh` | — | bats: short-TTL env auto-destroyed | …03-daemon | ☑ |
| A16 | Daemon actions timestamped in `logs/cleanup.log` | `platform/cleanup_daemon.sh` | — | bats: log line format | …03-daemon | ☑ |
| A17 | Daemon runs in background via `nohup` | `docker-compose.yml` (daemon service entrypoint) | `make up` | journaled startup logs | …03-daemon | ☑ |
| A18 | Nginx is the front door for all envs | `nginx/nginx.conf` + `docker-compose.yml` | — | Postman: env URL hits nginx | …01-skeleton | ☑ |
| A19 | Each create writes `nginx/conf.d/$ENV_ID.conf` and runs `nginx -s reload` | `platform/lib/nginx_render.sh` | — | bats: file exists + nginx pid stable | …02-lifecycle | ☑ |
| A20 | Each destroy deletes the conf and reloads | `platform/lib/nginx_render.sh` | — | bats: file absent + reload logged | …02-lifecycle | ☑ |
| A21 | `nginx.conf` includes `conf.d/*.conf` | `nginx/nginx.conf` | — | grep-based check | …01-skeleton | ☑ |
| A22 | Nginx runs as a Docker container | `docker-compose.yml` | `make up` | `docker compose ps nginx` | …01-skeleton | ☑ |
| A23 | Network approach documented in README | `README.md` § Architecture | — | — | …05-ship | ☑ |
| A24 | Log shipping approach picked and documented | `platform/create_env.sh` + README | — | bats: PID stored, killed on destroy (Approach A) | …03-daemon | ☑ |
| A25 | Logs queryable via `make logs ENV=...` | `Makefile` | `make logs ENV=…` | manual smoke | …03-daemon | ☑ |
| A26 | Health poller in `monitor/` hits `/health` every 30s | `monitor/health_poller.py` | — | bats: cadence check via timestamps | …03-daemon | ☑ |
| A27 | Writes timestamp, HTTP status, latency to `logs/$ENV_ID/health.log` | `monitor/health_poller.py` | — | bats: log format | …03-daemon | ☑ |
| A28 | After 3 consecutive failures → status `degraded` + warning printed | `monitor/health_poller.py` | — | bats: kill app, observe flip | …03-daemon | ☑ |
| A29 | `simulate_outage.sh` accepts `--env` and `--mode` | `platform/simulate_outage.sh` | `make simulate ENV=… MODE=…` | bats: arg parsing | …04-outage | ☑ |
| A30 | mode `crash` → docker kill | `platform/simulate_outage.sh` | — | bats + Postman: degraded within 90s | …04-outage | ☑ |
| A31 | mode `pause` → docker pause; recover with unpause | `platform/simulate_outage.sh` | — | bats: paused state visible in `docker inspect` | …04-outage | ☑ |
| A32 | mode `network` → docker network disconnect | `platform/simulate_outage.sh` | — | bats: connectivity broken, then restored on recover | …04-outage | ☑ |
| A33 | mode `recover` → restore broken state | `platform/simulate_outage.sh` | — | bats: recovers crash, pause, network | …04-outage | ☑ |
| A34 | Optional: mode `stress` (CPU spike) | `platform/simulate_outage.sh` | — | manual smoke if shipped | …04-outage | ☑ |
| A35 | Guard: never simulate against Nginx or daemon | `platform/lib/state.sh::assert_app_container` | — | bats: refusal exit 2 + msg | …04-outage | ☑ |
| A36 | Control API (Flask/FastAPI/Express) wraps the scripts | `platform/api.py` | `make up` | Postman: pre-flight | …04-outage | ☑ |
| A37 | `POST /envs` → create env | `platform/api.py` | — | Postman: Create env | …04-outage, journal/2026-05-10-06-ci-repair | ☑ |
| A38 | `GET /envs` → list active envs + TTL remaining | `platform/api.py` | — | Postman: List envs | …04-outage | ☑ |
| A39 | `DELETE /envs/:id` → destroy env | `platform/api.py` | — | Postman: Destroy env | …04-outage, journal/2026-05-10-06-ci-repair | ☑ |
| A40 | `GET /envs/:id/logs` → last 100 lines of app.log | `platform/api.py` | — | Postman: Get logs (asserts ≤100) | …04-outage | ☑ |
| A41 | `GET /envs/:id/health` → last 10 health check results | `platform/api.py` | — | Postman: Get health (asserts ≤10) | …04-outage | ☑ |
| A42 | `POST /envs/:id/outage` → trigger simulation, body `{"mode":"crash"}` | `platform/api.py` | — | Postman: Trigger outage | …04-outage, journal/2026-05-10-06-ci-repair | ☑ |
| A43 | `make up` starts Nginx + daemon + API | `Makefile` | `make up` | manual smoke | …01-skeleton, …04-outage | ☑ |
| A44 | `make down` stops everything, destroys all envs | `Makefile` | `make down` | bats: post-down repo-state clean | …05-ship | ☑ |
| A45 | `make create` creates new env (prompts for name + TTL) | `Makefile` | `make create` | manual smoke | …02-lifecycle | ☑ |
| A46 | `make destroy ENV=…` destroys specific env | `Makefile` | — | bats | …02-lifecycle | ☑ |
| A47 | `make logs ENV=…` tails env logs | `Makefile` | — | manual smoke | …03-daemon | ☑ |
| A48 | `make health` shows all env health statuses | `Makefile` | — | manual smoke | …03-daemon | ☑ |
| A49 | `make simulate ENV=… MODE=…` runs outage sim | `Makefile` | — | bats | …04-outage | ☑ |
| A50 | `make clean` wipes state, logs, archives | `Makefile` | — | bats: dirs empty post-run; root-owned archive regression smoke | …05-ship, journal/2026-05-12-01-clean-permission-repair | ☑ |
| A51 | README architecture diagram (ASCII or PNG) | `README.md` | — | — | …05-ship | ☑ |
| A52 | README prerequisites listed | `README.md` | — | — | …05-ship | ☑ |
| A53 | Quick-start ≤ 5 commands from zero to running env | `README.md` | — | manual replay on a fresh VM | …05-ship | ☑ |
| A54 | Full demo walkthrough in README | `README.md` | — | — | …05-ship | ☑ |
| A55 | Known limitations in README | `README.md` | — | — | …05-ship | ☑ |
| A56 | All secrets in `.env`, never committed | `.gitignore` + `.env.example` | — | gitleaks pass | journal/2026-05-09-01-bootstrap, journal/2026-05-11-08-local-cleanup | ☑ |
| A57 | 3-minute walkthrough video uploaded, link in README | (external, in README) | — | — | …05-ship | ☐ |
| A58 | Server live at grading time | GCP VM `sandbox-vm` | — | Newman against `http://34.77.247.217:18081` | journal/2026-05-10-07-readme-live-submission | ☑ |

## Section B — Implied requirements

These are not in the brief's bullet list, but a reviewer would dock points for missing them.

| # | Requirement | Code | Make target | Postman / test | Journal | ☑ |
|---|---|---|---|---|---|---|
| B01 | Atomic state-file writes (write→fsync→rename) | `platform/lib/state.sh::write_state_atomic` | — | bats: SIGKILL mid-write leaves state intact-or-absent | …02-lifecycle | ☑ |
| B02 | Idempotency: `destroy_env.sh missing-id` exits 0 | `platform/destroy_env.sh` | — | Postman: DELETE bogus id → 404, then 404 again | …02-lifecycle | ☑ |
| B03 | Idempotency: `make up` on running stack is a no-op | `Makefile` + compose | `make up` | manual smoke | …01-skeleton | ☑ |
| B04 | UTC ISO-8601 timestamps everywhere | `platform/lib/logging.sh::ts` | — | regex check across log files | …01-skeleton | ☑ |
| B05 | TTL parsed correctly from CLI flag and API body | `platform/create_env.sh` + `platform/api.py` | — | bats + Postman: TTL surfaces in state | …02-lifecycle | ☑ |
| B06 | Resource caps on env containers (cpus/mem/pids) | `platform/create_env.sh` | — | bats: `docker inspect` HostConfig | …02-lifecycle | ☑ |
| B07 | `--security-opt no-new-privileges` on env containers | `platform/create_env.sh` | — | bats: `docker inspect` SecurityOpt | …02-lifecycle | ☑ |
| B08 | Demo app exists and serves `/health` | `demo-app/app.py` | — | Postman pre-flight: env URL `/health` → 200 | …01-skeleton | ☑ |
| B09 | Demo app runs as non-root | `demo-app/Dockerfile` | — | bats: `docker inspect` User | …01-skeleton | ☑ |
| B10 | API authentication (optional, gated on `API_TOKEN` in `.env`) | `platform/api.py` | — | Postman: with token + without token branches | …04-outage | ☑ |
| B11 | Cleanup daemon traps SIGTERM/SIGINT | `platform/cleanup_daemon.sh` | — | bats: send SIGTERM, observe clean shutdown line | …03-daemon | ☑ |
| B12 | Pre-flight checks in `make up` | `Makefile::up` | `make up` | bats: cause each pre-flight to fail in turn | …01-skeleton | ☑ |
| B13 | `nginx -t` is run before every reload | `platform/lib/nginx_render.sh::reload_nginx` | — | bats: corrupt a conf, observe abort | …02-lifecycle | ☑ |
| B14 | `history.jsonl` event log (create/destroy/outage/degraded/cleanup) | `platform/lib/logging.sh::history` | — | grep-based shape check | all sprints | ☑ |
| B15 | `.env.example` documents every key | `.env.example` | — | diff against code's getenv calls | …00-bootstrap | ☑ |
| B16 | Conventional Commits enforced | `.pre-commit-config.yaml` (commitlint or commitizen hook) | — | dummy bad commit message rejected | journal/2026-05-09-01-bootstrap | ☑ |
| B17 | shellcheck clean on all `.sh` files | `governance/ci/shellcheck.sh` | — | CI gate | journal/2026-05-09-01-bootstrap | ☑ |
| B18 | API responses use a single error shape `{ "error": { "code": …, "message": … } }` | `platform/api.py` | — | Postman: error-path tests | …04-outage | ☑ |
| B19 | Orphan-resource sweeper (state file gone but container survives, vice versa) | `platform/cleanup_daemon.sh` | — | bats: orphan reconciliation | …03-daemon | ☑ |
| B20 | Disk-space guard: refuse new env if < 1 GiB free | `platform/create_env.sh` | — | bats: simulated low-space refusal | …02-lifecycle | ☑ |
| B21 | TTL has a documented upper bound (e.g., 240 minutes) | `manifest.yaml` + API validation | — | Postman: ttl=99999 → 400 | …04-outage | ☑ |
| B22 | Newman-runnable Postman pack in repo | `governance/postman/*` | `make test-api` | self-referential | …04-outage | ☑ |
| B23 | `make ship-check` aggregate gate | `Makefile::ship-check` | `make ship-check` | self-referential | …05-ship | ☑ |
| B24 | Architecture diagram regenerated when services change | `README.md` | — | manual review at end of sprint 5 | …05-ship | ☑ |
| B25 | `evidence/` proof bundle script | `scripts/capture_evidence.sh` | `make bundle-evidence` | manual review | …05-ship | ☑ |

## Section C — Quality / DevSecOps

| # | Requirement | Code | Make target | Postman / test | Journal | ☑ |
|---|---|---|---|---|---|---|
| C01 | gitleaks clean | `governance/ci/gitleaks.toml` → `.gitleaks.toml` | — | CI gate | journal/2026-05-09-01-bootstrap | ☑ |
| C02 | pre-commit hooks installed | `governance/ci/pre-commit-config.yaml` | — | local hook fire | journal/2026-05-09-01-bootstrap | ☑ |
| C03 | Trivy scan on every image build (optional, target if time) | `.github/workflows/ci.yml` | — | CI artifact: run 25628845899 | journal/2026-05-10-06-ci-repair | ☑ |
| C04 | GitHub Actions CI runs Newman against the local stack | `.github/workflows/ci.yml` | — | green check on PR | …05-ship | ☑ |
| C05 | OPA policies for create + outage (extra credit) | `policies/*.rego` | — | unit tests in `policies/test/` | …05-ship (if shipped) | ☐ |
| C06 | Local pre-commit hooks `governance-matrix-touched` and `journal-entry-on-feat` exist, are executable, and pass on a manufactured negative case (commit touching `platform/` without matrix update fails as expected) | `scripts/check_acceptance_matrix.sh`, `scripts/check_journal_today.sh` | — | manufactured-negative-case run inside WSL | journal/2026-05-09-01-bootstrap | ☑ |

## How the matrix is used

- The agent updates this matrix at the **end** of every session, in the same commit as the journal entry that closes the rows.
- A row goes ☑ only when its four reference cells point to real, committed artifacts. The `make ship-check` target greps this file for `☐` and exits non-zero if any are found in Sections A or B.
- Section C is allowed to have ☐ rows if `09_KNOWN_PITFALLS.md` lists them as conscious deferrals with a stated reason. Sections A and B are not.
