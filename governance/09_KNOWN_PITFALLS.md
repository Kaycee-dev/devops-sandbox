# 09 — Known Pitfalls

A list of failure modes the agent must consciously not fall into. Each entry has a name, a one-line cause, and a one-line guard. The guards are real things implemented in the code or scripts; this file points at where they live.

## A. Pitfalls explicitly called out by the brief

### A1. Hardcoded container names or ports
**Cause.** Copy-paste from a tutorial leaves `--name app-1` or `-p 3000:3000` in scripts.
**Guard.** Every `docker run` invocation must reference `${ENV_ID}` in its `--name` and read its port from `manifest.yaml`. Pre-commit hook `governance-no-hardcoded-ports` greps for `^[^#]*--name [a-z]+-[0-9]+\b` and refuses the commit.

### A2. Forgetting to reload Nginx after a config change
**Cause.** Writer function writes the file but the `nginx -s reload` is in the calling script and gets skipped on an early-return path.
**Guard.** `lib/nginx_render.sh::write_conf` and `delete_conf` *both* call `reload_nginx` themselves, with a `nginx -t` gate in between. Callers cannot forget because the helper is the only public API.

### A3. Not killing the log-shipping process on destroy (zombie processes)
**Cause.** `docker logs -f $CID > … &` is started in `create_env.sh` but the PID is not stored, or it is stored but `destroy_env.sh` skips killing it.
**Guard.** PID array `bg_pids` is part of the state-file schema (§State Schema, `10_API_CONTRACT.md`). `destroy_env.sh` iterates and `kill`s each, then verifies with `kill -0 $pid 2>/dev/null` that the process is gone. `bats` test asserts no `docker logs -f` processes survive a destroy.

### A4. Writing state files non-atomically
**Cause.** `echo "$json" > envs/$ENV_ID.json` interrupted leaves a half-file.
**Guard.** `lib/state.sh::write_state_atomic` writes to `.tmp.$ENV_ID.<pid>.json`, `fsync`s, then `mv`s. Constitution §2.2. `bats` test SIGKILLs mid-write and asserts the destination is intact-or-absent.

## B. Pitfalls not in the brief, but easy to fall into

### B1. The `make clean` nuke
**Cause.** `make clean` aggressively removes everything, including `.env`.
**Guard.** `make clean` removes `logs/`, `envs/`, `logs/archived/`, `evidence/`. It does **not** remove `.env`. The Makefile recipe lists every directory by name; no wildcards above the relevant level.

### B2. Cleanup daemon double-destroy race
**Cause.** Daemon ticks at T=60. Operator runs `destroy_env.sh` at T=60.5. Both attempt to remove the same Nginx conf; the second one's `nginx -s reload` happens against a config we already nuked.
**Guard.** `destroy_env.sh` is idempotent; missing artifacts produce a "not found, nothing to do" log line, never an error. `lib/nginx_render.sh::delete_conf` is `rm -f`, never `rm`.

### B3. State file referenced by the daemon mid-write
**Cause.** Daemon reads `envs/$ENV_ID.json` while `create_env.sh` is writing it. With non-atomic writes this is a partial-read; with atomic writes the daemon sees either the old version or the new, never half.
**Guard.** Atomic writes (A4 above). The daemon also rejects state files that fail JSON parse, with a warning log line, instead of crashing.

### B4. Nginx upstream resolution at config-load time
**Cause.** Nginx resolves `proxy_pass http://sandbox-${ENV_ID}-app:5000` once at config load. If the upstream container restarts and gets a new IP, Nginx caches the old one and 502s.
**Guard.** Each per-env Nginx conf uses a `resolver 127.0.0.11 valid=10s ipv6=off;` directive (Docker's embedded DNS) and assigns the upstream to a `set $upstream …; proxy_pass http://$upstream;` form, which forces re-resolution. Documented in the README's network section.

### B5. Unbounded log growth in long-running envs
**Cause.** A 240-minute TTL env doing chatty logging fills the disk.
**Guard.** `docker run` flags include `--log-opt max-size=10m --log-opt max-file=3`. The platform's own logs (`logs/cleanup.log`, `logs/api.log`) rotate via `logrotate.d` config that ships in `governance/ci/logrotate.conf` (created in Sprint 5 if time).

### B6. `nohup` daemon not actually daemonised under compose
**Cause.** Compose runs the daemon's entrypoint in the foreground; `nohup` inside the container is mostly cosmetic.
**Guard.** The daemon's container has `restart: unless-stopped`. Compose, not `nohup`, is what keeps it running. The README explains this — the brief's "nohup" wording is satisfied by the *script* being `nohup`-tolerant (signal handling, no terminal dependency), not by literally invoking nohup at the host level.

### B7. Health poller crashes on a freshly-creating env
**Cause.** State file exists but the container isn't ready; `requests.get(url, timeout=5)` raises `ConnectionError`; the poller's loop dies.
**Guard.** Poller wraps each request in `try/except (ConnectionError, Timeout)`, treats exceptions as a failure of the same flavour as a non-2xx HTTP response. The consecutive-failure counter increments; after 3, status flips to `degraded`, just like a real failure. The poller is also tolerant of the env state's status being `creating` — it skips polling that env until status becomes `running`.

### B8. Container exists but state file doesn't (orphan)
**Cause.** `create_env.sh` crashed between starting the container and writing the state file.
**Guard.** `cleanup_daemon.sh`'s reconciler enumerates running containers with the `sandbox.role=app` label, cross-checks against state files, and destroys orphans with a warning log. Acceptance row B19.

### B9. State file exists but container doesn't (zombie state)
**Cause.** Operator ran `docker rm` directly without going through `destroy_env.sh`.
**Guard.** Reconciler also covers this direction: state file with no matching container → mark `error`, log a warning, leave for human to call `destroy_env.sh` (which will succeed via its idempotent missing-artifact handling).

### B10. Reusing a port across envs
**Cause.** Two envs configured to bind the same host port; second create fails halfway.
**Guard.** Each env publishes through Nginx, not by binding a host port directly. The only host port in use is the public ingress port from `manifest.yaml` (default 18080). Sandbox containers expose their app port to their network, not to the host.

### B11. The token check that always passes
**Cause.** `if request.headers.get('X-API-Token') == os.getenv('API_TOKEN')`. If `API_TOKEN` is unset, both sides are `None` and the comparison passes.
**Guard.** Use `hmac.compare_digest`. Treat unset `API_TOKEN` as "auth disabled, log a warning at startup", not as a value to compare against.

### B12. The `make up` first-run amnesia
**Cause.** A reviewer clones the repo, runs `make up`, and gets a cryptic error because they didn't `cp .env.example .env` first.
**Guard.** `make up`'s first action checks for `.env`; if missing, it copies `.env.example` to `.env`, prints "Created `.env` from `.env.example`. Edit secrets and re-run." and exits 0. The README's quick-start lists this behaviour.

### B13. Nginx container can't reach sandboxnet networks
**Cause.** Nginx is on its own platform network; sandbox envs are on per-env networks; without explicit `docker network connect`, Nginx cannot resolve or reach them.
**Guard.** `create_env.sh`'s last step before reload is `docker network connect sandboxnet-${ENV_ID} sandbox-nginx`. `destroy_env.sh`'s first cleanup step is `docker network disconnect sandboxnet-${ENV_ID} sandbox-nginx` (with `--force` for safety). Documented in README's "Network approach" section.

### B14. Time zone surprise
**Cause.** `created_at` written as local time on a UTC VM; daemon reads it as UTC; TTL math is wrong by hours.
**Guard.** §4.1 of the constitution. `now()` is always `date -u`. State file values are always Z-suffixed.

### B15. The "I'll add tests later" trap
**Cause.** Sprint 2 finishes with happy-path scripts but no `bats` tests; sprint 3 builds on sprint 2 unverified; a regression in sprint 4 surfaces as Postman failures and the agent has no baseline.
**Guard.** Every sprint exit condition lists a `bats` test that must pass. `make ship-check` runs them. No "later."

### B16. Chrome 502 because of caching
**Cause.** Reviewer creates env, hits URL in Chrome, sees 502 momentarily, refreshes — Chrome caches the 502.
**Guard.** Per-env Nginx conf sets `add_header Cache-Control "no-store" always;` on the env's `/health` endpoint. The README's demo walkthrough also tells the reviewer to use `curl`, not a browser.

## Conscious deferrals (acceptable ☐ rows)

If any of these are not shipped by deadline, mark the corresponding acceptance row as ☐ with a note pointing to this section:

- **C03** Trivy scan in CI — only if Sprints 0–4 all green and ≥ 4 hours remain.
- **C05** OPA policy enforcement (sandbox_create.rego, sandbox_outage.rego) — extra credit, defer if needed.
- **A34** `stress` outage mode — explicitly listed as optional in the brief.
- **Prometheus + Grafana** — explicitly listed as optional extra credit.

Anything else marked as a conscious deferral requires a written justification in the journal entry that introduced it as deferred.
