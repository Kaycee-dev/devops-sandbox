# 00 — Repo Index

A one-page map of the whole `devops-sandbox` repository. Updated by the agent at the end of every session. If a file exists in the repo and is not on this map, it gets added; if it is on this map and does not exist, it gets removed. Staleness here is a smell.

## Top-level layout (target shape)

```
devops-sandbox/
├── governance/                 # this pack — read first, every session
├── platform/
│   ├── create_env.sh
│   ├── destroy_env.sh
│   ├── cleanup_daemon.sh
│   ├── simulate_outage.sh
│   ├── api.py                  # FastAPI control plane
│   └── lib/
│       ├── state.sh            # atomic state-file helpers
│       ├── env_id.sh           # ID generation, validation
│       ├── nginx_render.sh     # conf.d/ writers + reload
│       └── logging.sh          # ts() and structured-log helpers
├── nginx/
│   ├── nginx.conf              # includes conf.d/*.conf
│   └── conf.d/                 # generated per-env configs (.gitkeep only)
├── monitor/
│   └── health_poller.py        # 30s loop, degraded-after-3 logic
├── demo-app/
│   ├── Dockerfile              # the thing that runs *inside* a sandbox env
│   ├── app.py                  # Flask /health + / endpoint
│   └── requirements.txt
├── manifest.yaml               # source of truth for defaults, ports, image name
├── docker-compose.yml          # Nginx + API + cleanup daemon + monitor
├── Makefile                    # targets per the brief, plus ship-check / test-api
├── .env.example                # documented placeholders only
├── .gitignore                  # blocks .env, logs/, envs/
├── .dockerignore
├── .gitleaks.toml              # symlink or copy of governance/ci/gitleaks.toml
├── .pre-commit-config.yaml     # symlink or copy of governance/ci/pre-commit-config.yaml
├── README.md                   # generated from governance/templates/README_skeleton.md
├── journal/                    # one entry per working session
│   └── YYYY-MM-DD-NN-<slug>.md
├── policies/                   # OPA Rego (extra credit)
│   ├── sandbox_create.rego
│   └── sandbox_outage.rego
├── scripts/
│   └── capture_evidence.sh     # produces the proof bundle for the demo video
├── logs/                       # gitignored
└── envs/                       # gitignored
```

## What lives where, in plain English

- **`governance/`** — the rules. Authoritative. Never modified during a code session except for the acceptance matrix and (rarely) the pitfalls list.
- **`platform/`** — the four bash scripts plus the Python control API. The scripts are the engine; the API wraps them. The `lib/` subdirectory is shared bash helpers so we never repeat ourselves.
- **`nginx/`** — front door config. `conf.d/` is empty in git (just a `.gitkeep`); the per-env `.conf` files are written at runtime by `create_env.sh` and removed by `destroy_env.sh`.
- **`monitor/`** — the health poller. Runs as its own container in `docker-compose.yml`. Reads `envs/*.json`, hits each env's `/health`, writes to `logs/$ENV_ID/health.log`, flips status to `degraded` after 3 consecutive failures.
- **`demo-app/`** — the *thing* that gets deployed inside each sandbox environment. The brief says it can be anything; we ship a tiny Flask app with `/` and `/health`, because that's the simplest thing that proves the platform works.
- **`manifest.yaml`** — the source of truth for everything not encoded in scripts: default TTL, port range, container image name, resource caps. Mirrors the Stage 4A pattern.
- **`docker-compose.yml`** — runs the *platform* services (Nginx, API, cleanup daemon, monitor). The sandbox envs themselves are *not* in compose; they are spun up by `create_env.sh` and live on their own Docker networks.
- **`Makefile`** — the brief lists 8 required targets; we add `test-api`, `ship-check`, `bundle-evidence`. Every target prints its own usage when called wrong.
- **`journal/`** — one Markdown file per working session. Numbered within the day so multiple sessions don't collide. Frontmatter required.
- **`policies/`** — OPA Rego stubs. Extra credit. If the API is asked to refuse a create or an outage on policy grounds, this is where the decision lives.
- **`scripts/capture_evidence.sh`** — runs the full demo flow end-to-end and saves screenshots/log excerpts under `evidence/`, ready to paste into the 3-minute video.

## Files explicitly required by `CURRENT_TASK`

| Required file/path                     | Where in our layout                          |
|----------------------------------------|----------------------------------------------|
| `platform/create_env.sh`               | `platform/create_env.sh`                     |
| `platform/destroy_env.sh`              | `platform/destroy_env.sh`                    |
| `platform/cleanup_daemon.sh`           | `platform/cleanup_daemon.sh`                 |
| `platform/api.py`                      | `platform/api.py`                            |
| `platform/simulate_outage.sh`          | `platform/simulate_outage.sh`                |
| `nginx/nginx.conf`                     | `nginx/nginx.conf`                           |
| `nginx/conf.d/`                        | `nginx/conf.d/.gitkeep`                      |
| `monitor/` (health poller)             | `monitor/health_poller.py`                   |
| `logs/` (gitignored)                   | `logs/` + `.gitignore` rule                  |
| `envs/` (gitignored)                   | `envs/` + `.gitignore` rule                  |
| `Makefile`                             | `Makefile`                                   |
| `README.md`                            | `README.md`                                  |
| `.env`                                 | `.env` (gitignored) + `.env.example`         |

## Update protocol

After each session, the agent runs:

```bash
tree -L 3 -a -I '.git|node_modules|__pycache__|logs|envs|.venv' > /tmp/tree.txt
diff /tmp/tree.txt <(grep -A 999 '^```$' governance/00_INDEX.md | sed -n '/^├\|^└\|^│\|^devops-sandbox/p')
```

and reconciles any drift before committing the journal entry.
