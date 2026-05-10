---
date: 2026-05-10
session: 01
slug: skeleton-and-demo-app
sprint: 1
duration_minutes: 25
files_touched:
  - journal/2026-05-10-01-skeleton-and-demo-app.md
  - manifest.yaml
  - demo-app/app.py
  - demo-app/Dockerfile
  - platform/Dockerfile
  - platform/requirements.txt
  - platform/api.py
  - nginx/nginx.conf
  - docker-compose.yml
  - Makefile
acceptance_rows_closed: [A21, A22, A43, B03, B08, B09, B12]
acceptance_rows_in_progress: []
---

## PLAN

Sprint 1 builds the runnable skeleton: a manifest-driven platform config, a known-good non-root demo app, the Nginx front door, compose-managed platform services, and idempotent `make up` / `make down` targets with pre-flight checks. The goal is not lifecycle completeness yet; it is to make the platform boot in one command so Sprints 2-4 have a stable substrate.

- [ ] Write `manifest.yaml` with defaults, service names, ports, image refs, and resource caps.
- [ ] Add the demo Flask app and Dockerfile; `/` and `/health` must be deterministic.
- [ ] Add `nginx/nginx.conf` with `conf.d/*.conf` included and a root landing response.
- [ ] Add `docker-compose.yml` with Nginx, API, daemon, and monitor platform services.
- [ ] Replace the Makefile stub with idempotent `up`, `down`, `clean`, `help`, and Sprint-1-safe placeholders for later targets.
- [ ] Run the Sprint 1 gate: `make up`, root curl, `docker exec sandbox-nginx nginx -t`, `docker compose ps`, `make down`.

Targeted rows: A21, A22, A43, B03, B08, B09, B12

## TEACH-BACKS

### TEACH-BACK: Keep `manifest.yaml` as the runtime source of truth

**Context.** Sprint 1 needs both `docker-compose.yml` and later bash/API code to agree on ports, image names, service names, and resource caps. Constitution §1.2 says `manifest.yaml` is the runtime source of truth for those values.

**Alternatives considered**
1. **Hardcode Sprint 1 constants directly in compose and scripts** — fastest for the first gate, but it creates the exact drift that §1.2 is meant to prevent.
2. **Create `manifest.yaml` now and let later scripts read or mirror it deliberately** — slightly more typing, but it gives every sprint one obvious place to audit defaults.

**Chosen** — **create `manifest.yaml` now**, because Constitution §1.2 makes it the source of truth and the acceptance matrix later checks that resource caps, ports, and image refs are not scattered through the code.

**Failure modes**
- Compose cannot interpolate nested YAML values from the manifest directly, so Sprint 1 may still duplicate values in `docker-compose.yml`.
- Later scripts may parse YAML with brittle shell snippets if we do not centralize manifest reads in Sprint 2.

**Reversal cost.** Low during Sprint 1; medium after lifecycle scripts start depending on the shape.

**Citations.**
- `governance/01_CONSTITUTION.md` §1.2
- `governance/02_SPRINT_PLAN.md` Sprint 1 task 1

### TEACH-BACK: Use Nginx-only host ingress with per-env containers kept off host ports

**Context.** The brief requires Nginx to be the front door. Known pitfall B10 warns that binding host ports per environment creates collision and cleanup problems.

**Alternatives considered**
1. **Publish each app container on a random host port** — easy to test with `curl`, but it weakens the platform model and makes the API expose implementation details.
2. **Expose only Nginx on `18080` and put sandbox containers on Docker networks** — more network setup, but it matches the final dynamic routing design.

**Chosen** — **Nginx-only host ingress**, because it closes A21/A22 cleanly and preserves the lifecycle design needed for A18-A20 without port collisions.

**Failure modes**
- Nginx must be explicitly connected to each per-env network in Sprint 2; missing that step produces 502s.
- Docker DNS re-resolution must be handled in generated per-env configs, or restarted app containers can become unreachable.

**Reversal cost.** Medium. Changing after API URLs are published would alter the public contract and README walkthrough.

**Citations.**
- `governance/CURRENT_TASK` §3, Nginx Dynamic Routing
- `governance/09_KNOWN_PITFALLS.md` B10 and B13

## NOTES

- CRISIS mode compresses teach-backs to 1-2 real decisions for the sprint. I am using two blocks here and keeping smaller choices inside this entry's outcomes.
- Existing dirty files at session start were executable-bit drift only: `ci/shellcheck.sh`, `governance/ci/shellcheck.sh`, `scripts/check_acceptance_matrix.sh`, and `scripts/check_journal_today.sh`.

## OUTCOMES

```
$ make test-api
not run in Sprint 1 - API contract landed in Sprint 4
```

```
$ make up
PASS - Nginx, API, daemon, and monitor started.

$ curl -fsSL http://localhost:18080/
sandbox platform ok

$ docker exec sandbox-nginx nginx -t
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

## LEARNINGS

- A standalone `nginx -t` container cannot resolve compose DNS names at config-test time; proxy targets need runtime resolution through variables if preflight runs before the compose network exists.
- The platform image needs to exist as `devops-sandbox-api:latest` early because CI/Trivy refers to that tag.

## BLOCKERS

none

## NEXT

Sprint 2/3 should build lifecycle, daemon, log shipping, and health monitoring on top of this bootable skeleton.
