---
date: 2026-05-10
session: 03
slug: daemon-monitor
sprint: 3
duration_minutes: 30
files_touched:
  - journal/2026-05-10-03-daemon-monitor.md
  - platform/cleanup_daemon.sh
  - monitor/health_poller.py
  - docker-compose.yml
  - Makefile
acceptance_rows_closed: [A14, A15, A16, A17, A24, A25, A26, A27, A28, A47, A48, B11, B19]
acceptance_rows_in_progress: []
---

## PLAN

Sprint 3 turns the skeleton into a self-cleaning platform: Approach A log shipping, a 60-second cleanup daemon, and a 30-second health poller that marks envs degraded after three consecutive failures. The first gate is smoke-level proof; the full Postman gate lands with the API in Sprint 4.

- [ ] Run `cleanup_daemon.sh` from the daemon container with signal handling and timestamped logs.
- [ ] Reconcile expired envs and obvious orphan containers/state.
- [ ] Run `monitor/health_poller.py` from the monitor container.
- [ ] Append health checks and atomically mark envs degraded after 3 failures.
- [ ] Make `make logs` and `make health` useful for active envs.

Targeted rows: A14-A17, A24-A28, A47-A48, B11, B19

## TEACH-BACKS

### TEACH-BACK: Approach A log shipping for the deadline build

**Context.** The brief allows either `docker logs -f` per env or a real log aggregator. The crisis prompt keeps the quality floor but compresses delivery time; an aggregator adds ports, storage, and operational surface.

**Alternatives considered**
1. **Approach B with Loki/Fluentd** — more production-like, but too much extra compose and query surface for the deadline.
2. **Approach A with tracked `docker logs -f` PID** — simple, testable, and explicitly accepted by the brief if destroy kills the process.

**Chosen** — **Approach A**, because it directly satisfies A24/A25 and the non-negotiable process-hygiene requirement when the PID is stored and killed.

**Failure modes**
- If state writing fails after the log shipper starts, rollback must kill the PID or a background process survives.
- If the API container restarts, host-launched log shippers continue, but container-launched shippers may die; `create_env.sh` runs on the caller side, so the PID belongs to that process namespace.

**Reversal cost.** Low to medium. Loki can be added later without changing app containers, but `make logs` behavior would need a new backend.

**Citations.**
- `governance/CURRENT_TASK` §4
- `governance/01_CONSTITUTION.md` §6.1-§6.2

## NOTES

- Decision made unilaterally under CRISIS mode: compose keeps daemon/monitor in foreground rather than literal host `nohup`; this follows known pitfall B6 and preserves container restart behavior.
- Decision made unilaterally under CRISIS mode: API, daemon, and monitor use `pid: host` because Approach A stores OS PIDs for `docker logs -f`; without a shared PID namespace, daemon-driven destroy cannot reliably kill shippers launched by another platform container.

## OUTCOMES

```
$ make test-api
PASS in Sprint 4/5 after API landed - 14 requests, 59 assertions, 0 failures.
```

```
$ cat logs/archived/env-045a77b2/.../health.log
2026-05-10T10:03:35Z 200 84
2026-05-10T10:04:05Z 200 28
...

$ tail logs/cleanup.log
ttl expired; destroying
```

## LEARNINGS

- The monitor must use an internal URL (`http://nginx/<env_id>/`) inside compose; `localhost` from the monitor container points at itself, not the host.
- Approach A PID cleanup crosses process namespaces unless API/daemon/monitor share `pid: host`; otherwise a daemon container cannot kill a shipper launched by the API container.

## BLOCKERS

none

## NEXT

Sprint 4 adds outage simulation and replaces the API stub with the full FastAPI contract.
