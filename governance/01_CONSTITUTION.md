# 01 — Constitution

These rules are non-negotiable. The agent does not relax them, the human does not relax them, and "we'll come back to fix it later" is not a defence. Every clause has a number; the journal cites the number when a teach-back block invokes a clause.

## §1 — Source of truth

**§1.1** `governance/CURRENT_TASK` is the verbatim brief. It is never paraphrased into another file.
**§1.2** `manifest.yaml` is the runtime source of truth for defaults, ports, image names, and resource caps. `nginx.conf`, `docker-compose.yml`, and the API's config object are derived from it.
**§1.3** Generated files carry a `# GENERATED — do not edit by hand` header, with a path to the generator.

## §2 — State files

**§2.1** State files live under `envs/$ENV_ID.json`. Schema is fixed in `10_API_CONTRACT.md` §State Schema; any change requires a contract update first.
**§2.2** Every write is atomic: write to `envs/.tmp.$ENV_ID.<pid>.json`, `fsync`, then `mv` into place. No exceptions. (Brief, "Common Mistakes", line 4.)
**§2.3** Reads tolerate the absence of optional fields and reject the absence of required fields with a clear error.
**§2.4** Status field has a closed enum: `creating | running | degraded | destroying | error`. No free-text statuses.

## §3 — Identifiers and naming

**§3.1** `ENV_ID` is generated as `env-<8 hex chars>` (e.g. `env-a3f9b2c1`). It is URL-safe, uniquely greppable, and shorter than a docker container name limit.
**§3.2** Container names are `sandbox-${ENV_ID}-app`. Network names are `sandboxnet-${ENV_ID}`. Nginx config files are `nginx/conf.d/${ENV_ID}.conf`. **Nothing** is named without an `${ENV_ID}` segment, except the platform containers themselves (`sandbox-nginx`, `sandbox-api`, `sandbox-daemon`, `sandbox-monitor`).
**§3.3** Container labels: every sandbox env container carries `sandbox.env=$ENV_ID`, `sandbox.role=app`, `sandbox.created_at=<UTC ISO-8601>`. Platform containers carry `sandbox.role=nginx|api|daemon|monitor` and **never** carry `sandbox.env`.

## §4 — Time

**§4.1** All timestamps are UTC ISO-8601 with second precision: `2026-05-12T13:42:08Z`. No locale strings, no epoch-only fields without an ISO companion.
**§4.2** TTLs are stored as integer minutes in state files; surfaced as integer seconds in API responses (`ttl_remaining_seconds`).
**§4.3** `now()` in scripts is `date -u +%Y-%m-%dT%H:%M:%SZ`. In Python it is `datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')`.

## §5 — Nginx discipline

**§5.1** Every write to `nginx/conf.d/*.conf` is followed by a reload of the running Nginx container: `docker exec sandbox-nginx nginx -t && docker exec sandbox-nginx nginx -s reload`. The `-t` test gate is mandatory.
**§5.2** Every delete is followed by the same reload sequence. (Brief, "Common Mistakes", line 2.)
**§5.3** `nginx.conf` includes `conf.d/*.conf` and contains no per-env state. If the file ever needs editing for a per-env reason, that is a bug.
**§5.4** A failed `nginx -t` aborts the operation. The conf file that caused the failure is moved to `nginx/conf.d/.broken/${ENV_ID}.conf.<ts>` for forensics, never silently retried.

## §6 — Process hygiene

**§6.1** Background processes started by `create_env.sh` (e.g. `docker logs -f &` if Approach A is chosen) record their PID into the env state file's `bg_pids` array.
**§6.2** `destroy_env.sh` reads `bg_pids` and `kill`s each PID, then verifies with `kill -0 $pid 2>/dev/null` and `wait`s. (Brief, "Common Mistakes", line 3.)
**§6.3** `cleanup_daemon.sh` traps `SIGTERM` and `SIGINT`, exits its loop cleanly, and writes a `daemon stopped` line to `logs/cleanup.log`. No abrupt exits.

## §7 — Idempotency

**§7.1** `create_env.sh foo` called twice with the same name returns the same env (or a clear "already exists" error if the brief's spec disallows reuse). Decision is documented in the journal and reflected in `10_API_CONTRACT.md`.
**§7.2** `destroy_env.sh missing-id` exits 0 with a "not found, nothing to do" log line, never 1.
**§7.3** All Make targets are safe to run twice. `make up` on an already-up stack is a no-op.

## §8 — Outage simulation guard

**§8.1** `simulate_outage.sh` first inspects the target container's labels. If `sandbox.role` is anything other than `app`, the script aborts with exit code 2 and prints `refusing to simulate outage on platform container: <name>`. (Brief, §6 last line.)
**§8.2** The guard is a function in `platform/lib/state.sh` (`assert_app_container`) and is unit-tested by a one-line `bats` assertion in `tests/lib_state.bats` (or the equivalent bash test we ship).

## §9 — Secrets

**§9.1** No secret value is committed. Ever. `.env` is gitignored; `.env.example` lists every key with a placeholder.
**§9.2** `gitleaks` runs in pre-commit; CI fails on any leak.
**§9.3** The `.env` file's mode is `600`. `make up` checks this and refuses to start if it is more permissive.

## §10 — Logging

**§10.1** Every script logs in this format: `<UTC ISO-8601> <level> <component> <env_id|->  <message>`. Helper: `log INFO create_env $ENV_ID "starting"`.
**§10.2** `logs/$ENV_ID/app.log` is the demo-app stdout/stderr. `logs/$ENV_ID/health.log` is the health poller. `logs/cleanup.log` is the daemon. `logs/api.log` is the control API. Each goes only to its file; no cross-pollination.
**§10.3** `history.jsonl` (repo root) is an append-only event log: one JSON object per line, with `ts`, `event`, `env_id`, and event-specific fields. Mirrors Stage 4A's pattern. Used by the audit report.

## §11 — Pre-flight checks

`make up` runs, in order, and fails loudly on any miss:

**§11.1** `docker info` exits 0.
**§11.2** Compose v2 present (`docker compose version`).
**§11.3** Free disk space ≥ 2 GiB on the volume holding `logs/` and `envs/`.
**§11.4** `.env` exists and is mode `600`.
**§11.5** `nginx/nginx.conf` parses (`nginx -t -c $PWD/nginx/nginx.conf`).
**§11.6** No port collision on the public ingress port from `manifest.yaml`.

## §12 — Resource caps on sandbox containers

**§12.1** Every env container is started with `--cpus=1.0 --memory=512m --pids-limit=256`. Values come from `manifest.yaml`. The platform must not be DoS-able by a single bad sandbox env.
**§12.2** A `--read-only` filesystem with a `tmpfs` for `/tmp` is the default; the demo app honours this.
**§12.3** `--security-opt no-new-privileges` is set on every env container.

## §13 — Tests and gates

**§13.1** The Postman collection in `governance/postman/` is the integration-test suite. `make test-api` runs it via Newman against the local stack.
**§13.2** `make ship-check` is green before any push to `main`. It runs: pre-commit, gitleaks, shellcheck, the Postman pack, and the acceptance-matrix completeness check.
**§13.3** A red gate is never bypassed. `--no-verify` is forbidden.

## §14 — Documentation

**§14.1** Every change to a public surface (Make target, API endpoint, env var) is reflected in `README.md` in the same commit.
**§14.2** The architecture diagram in `README.md` is regenerated whenever a service is added or removed.
**§14.3** The journal entry that introduced a change is linked from the README's "Changelog" section.

## §15 — Conventional Commits

**§15.1** Commit messages follow `<type>(<scope>): <subject>` per Conventional Commits. Types: `feat | fix | chore | refactor | docs | test | ci | perf | build`.
**§15.2** The body references the journal entry: `journal: 2026-05-09-01-bootstrap.md`.
**§15.3** Breaking changes carry a `BREAKING CHANGE:` footer with a one-line migration note.

---

*If a clause feels too strict, raise it in the journal and propose an amendment. Do not silently violate it.*
