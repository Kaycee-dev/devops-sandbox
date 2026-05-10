# 07 — DevSecOps Guardrails

The brief does not list security as a graded section. The agent treats it as graded anyway, because:
- The platform mounts the Docker socket into the API container — that is a privilege boundary, and any leak there is full host compromise.
- The platform runs arbitrary code in sandbox env containers — that is the whole point — and we therefore take container hardening seriously.
- A leaked secret in a public repo is a real failure with real cleanup cost, regardless of grading.

## §1 — Secrets

**§1.1** Secrets live in `.env`. `.env` is in `.gitignore`. Period.

**§1.2** `.env.example` is committed and lists every key. Every getenv call in code corresponds to a key in `.env.example`. The pre-commit hook diffs them and fails on drift.

**§1.3** `.env` mode is `600` (owner read-write only). `make up` checks this and refuses to start if mode is more permissive.

**§1.4** `gitleaks` runs in pre-commit and in CI on every push. The repo's `.gitleaks.toml` (see `governance/ci/gitleaks.toml`) inherits the default ruleset and adds a custom rule for `API_TOKEN` and any `*_KEY` patterns.

**§1.5** If a secret is ever committed by mistake:
1. Rotate the secret immediately.
2. Use `git filter-repo` (or BFG) to scrub history.
3. Force-push, document in the journal under BLOCKERS.
4. Notify Kelechi. No silent cleanups.

## §2 — Container hardening

**§2.1** Every sandbox env container starts with:
```
--cpus=1.0 --memory=512m --pids-limit=256 \
--read-only --tmpfs /tmp:rw,nosuid,size=64m \
--security-opt no-new-privileges \
--cap-drop=ALL --cap-add=NET_BIND_SERVICE \
--user 1000:1000
```

**§2.2** The demo app's Dockerfile uses a minimal base image (`python:3.12-slim` or `python:3.12-alpine`), copies only what is needed, runs as a non-root user, and exposes only its app port. No `apt-get install -y curl bash net-tools git build-essential` cargo-cult.

**§2.3** Multi-stage Dockerfile: dependencies are installed in a builder stage, copied to a minimal runtime stage. The final image carries no compilers or package managers.

**§2.4** Image tag is pinned by digest in `manifest.yaml`. `latest` is forbidden.

## §3 — Network isolation

**§3.1** Each sandbox env runs on its own Docker network: `sandboxnet-${ENV_ID}`. Cross-env traffic is impossible by default.

**§3.2** The Nginx container is connected to every sandbox network at create-time and disconnected at destroy-time. This is the only way a single front-door reverse-proxies a fleet of isolated networks. The README explains this.

**§3.3** The platform services (API, daemon, monitor) live on a dedicated `sandboxnet-platform` network. They reach the Nginx container by service name; they do not need to be on per-env networks.

**§3.4** Nothing inside a sandbox env container can reach the Docker socket, the API, or the daemon. The platform reaches the env containers; the env containers do not reach the platform.

## §4 — Docker socket exposure (the elephant)

The API container needs to call `docker run`, `docker rm`, `docker network create/disconnect`, `docker exec` on the Nginx container, and `docker logs`. The simplest way to give it that ability is to mount `/var/run/docker.sock` into the API container. That is a full host-compromise primitive — anyone who reaches the API can run arbitrary containers as root on the host.

We do this anyway, because the alternatives (a docker-in-docker sidecar, a privileged shell-out service, an SSH-based remote agent) are all worse for a single-VM submission. We mitigate as follows:

**§4.1** The API does not accept arbitrary commands; it accepts a fixed set of typed endpoints, each of which calls a specific bash script. There is no `POST /shell` endpoint, no string-interpolated docker invocations.

**§4.2** All bash scripts that take user input quote every variable (`"$ENV_ID"`, never `$ENV_ID`), use `--end-of-options` (`--`) before any user-controlled positional argument, and validate input against a regex *before* using it.

**§4.3** The `X-API-Token` header is enforced when `API_TOKEN` is set in `.env`. The deployed environment sets it; local dev may leave it unset.

**§4.4** The README's "Known limitations" section names the docker-socket exposure explicitly. We do not pretend it isn't there.

## §5 — Input validation

**§5.1** `name` field on `POST /envs` matches `^[a-z][a-z0-9-]{0,31}$`. Anything else returns 400.

**§5.2** `ttl_minutes` is an integer in `[1, 240]`. Out of range returns 400.

**§5.3** `mode` field on outage is in `{crash, pause, network, recover, stress}`. Anything else returns 400.

**§5.4** `:id` in URL paths matches `^env-[0-9a-f]{8}$`. Anything else returns 404 (not 400, deliberately — we do not want to leak whether a malformed id "would have" matched).

## §6 — Logging hygiene

**§6.1** Logs never contain the `API_TOKEN` value, even partially. The token is read once at startup and compared via `hmac.compare_digest`; it is not logged on receive.

**§6.2** Logs contain client IP, env ID, endpoint, status code, latency. No request bodies (which might contain tokens or future PII).

**§6.3** Log files have mode `640` (owner rw, group r). Logs directory has mode `750`.

## §7 — Supply chain

**§7.1** Python dependencies in `requirements.txt` are pinned by version + hash (`pip install --require-hashes`). The pin set is regenerated by `pip-compile --generate-hashes` and committed.

**§7.2** Every Dockerfile starts with a pinned `FROM image:tag@sha256:digest`.

**§7.3** Trivy (or grype) scans every image at build time. The CI workflow attaches the scan output as a job artifact. High/critical findings fail the pipeline if they exist on packages we control; findings on the base image are noted but do not auto-fail (the agent decides per-finding).

## §8 — Pre-commit hooks (full set)

```
trailing-whitespace
end-of-file-fixer
check-yaml
check-json
check-merge-conflict
detect-private-key
gitleaks
shellcheck             # all *.sh
hadolint               # all Dockerfile
ruff (lint+format)     # all *.py
shfmt                  # all *.sh
commitlint             # commit message format
governance-matrix      # local hook: every commit body must reference a journal entry
```

## §9 — CI gates

`ci.yml` runs on every push and PR:

1. Checkout, set up Python 3.12, set up Docker buildx.
2. `pip install -r requirements.txt`.
3. `pre-commit run --all-files`.
4. `gitleaks detect --source . --redact -v`.
5. `shellcheck $(git ls-files '*.sh')`.
6. `hadolint $(git ls-files Dockerfile '*.Dockerfile')`.
7. `docker compose build`.
8. `trivy image --severity HIGH,CRITICAL --exit-code 1 sandbox-demo:1.0.0`.
9. `make up && make test-api`.
10. `make down`.

A red CI is never bypassed with `--no-verify` or admin force-merge. If a CI gate is broken (false positive), it is fixed in the same PR or surgically disabled with a documented `# noqa: <reason>` and a journal note.

## §10 — Threat model (one-page)

The threat model lives in `governance/THREAT_MODEL.md` (created during Sprint 5 if time). The single most important sentence in it:

> *We trust no one who can reach the API except the operator running it on the same VM. The API token, when set, is the only line between "I can list your envs" and "I can run arbitrary containers as root on your VM."*

That sentence shapes every decision.
