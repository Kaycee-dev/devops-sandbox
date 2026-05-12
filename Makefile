# DevOps Sandbox Platform - see governance/06_DEFINITION_OF_DONE.md
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.SILENT:
.DEFAULT_GOAL := help

COMPOSE := docker compose
ENV_FILE := .env
DEMO_IMAGE := $(shell awk -F': ' '/^[[:space:]]+image:/ {print $$2; exit}' manifest.yaml)
INGRESS_PORT ?= $(shell sed -n 's/^INGRESS_PORT=//p' .env 2>/dev/null || printf '18080')
API_PORT ?= $(shell sed -n 's/^API_PORT=//p' .env 2>/dev/null || printf '18081')
DEFAULT_TTL_MIN ?= $(shell sed -n 's/^DEFAULT_TTL_MIN=//p' .env 2>/dev/null || printf '30')

.PHONY: help up preflight down create destroy logs health simulate clean test-api ship-check lint format bundle-evidence

help:
	printf '%s\n' "DevOps Sandbox targets:"
	printf '%s\n' "  make up                         Start Nginx, API, daemon, and monitor"
	printf '%s\n' "  make down                       Stop the platform containers"
	printf '%s\n' "  make create                     Create an environment (Sprint 2)"
	printf '%s\n' "  make destroy ENV=env-abc12345   Destroy an environment"
	printf '%s\n' "  make logs ENV=env-abc12345      Tail app logs"
	printf '%s\n' "  make health                     Show health status"
	printf '%s\n' "  make simulate ENV=... MODE=...  Run outage simulation"
	printf '%s\n' "  make clean                      Wipe runtime state and generated logs, including Docker-owned archives"
	printf '%s\n' "  make test-api                   Run the Postman API suite"

up:
	if [[ ! -f "$(ENV_FILE)" ]]; then
	    cp .env.example "$(ENV_FILE)"
	    chmod 600 "$(ENV_FILE)"
	    printf '%s\n' "Created .env from .env.example. Review it, then run make up again."
	    exit 0
	fi
	$(MAKE) preflight
	docker build -t "$(DEMO_IMAGE)" demo-app
	$(COMPOSE) up -d --build api daemon monitor nginx

preflight:
	docker info >/dev/null
	$(COMPOSE) version >/dev/null
	mode="$$(stat -c '%a' "$(ENV_FILE)")"
	if [[ "$$mode" != "600" ]]; then
	    printf '%s\n' "ERROR: $(ENV_FILE) must be mode 600; run: chmod 600 $(ENV_FILE)" >&2
	    exit 1
	fi
	mkdir -p envs logs logs/archived nginx/conf.d nginx/conf.d/.broken
	free_kb="$$(df -Pk . | awk 'NR == 2 { print $$4 }')"
	if (( free_kb < 2097152 )); then
	    printf '%s\n' "ERROR: need at least 2 GiB free for logs/envs" >&2
	    exit 1
	fi
	if command -v ss >/dev/null 2>&1; then
	    if ss -ltn "sport = :$(INGRESS_PORT)" | grep -q LISTEN; then
	        if ! docker ps --format '{{.Names}}' | grep -qx 'sandbox-nginx'; then
	            printf '%s\n' "ERROR: port $(INGRESS_PORT) is already in use" >&2
	            exit 1
	        fi
	    fi
	fi
	docker run --rm \
	    -v "$$(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
	    -v "$$(pwd)/nginx/conf.d:/etc/nginx/conf.d:ro" \
	    nginx:1.27-alpine nginx -t

down:
	if [[ -d envs ]]; then
	    for state in envs/env-*.json; do
	        [[ -e "$$state" ]] || continue
	        env_id="$$(basename "$$state" .json)"
	        if [[ -x platform/destroy_env.sh ]]; then
	            bash platform/destroy_env.sh "$$env_id" || true
	        fi
	    done
	fi
	$(COMPOSE) down --remove-orphans

create:
	if [[ -x platform/create_env.sh ]]; then
	    if [[ -n "$${NAME:-}" ]]; then
	        ttl_arg=()
	        if [[ -n "$${TTL:-}" ]]; then
	            ttl_arg=(--ttl-minutes "$$TTL")
	        fi
	        bash platform/create_env.sh --name "$$NAME" "$${ttl_arg[@]}"
	    else
	        printf 'Name: '
	        read -r name
	        printf 'TTL minutes [%s]: ' "$(DEFAULT_TTL_MIN)"
	        read -r ttl
	        ttl="$${ttl:-$(DEFAULT_TTL_MIN)}"
	        bash platform/create_env.sh --name "$$name" --ttl-minutes "$$ttl"
	    fi
	else
	    printf '%s\n' "create_env.sh lands in Sprint 2" >&2
	    exit 2
	fi

destroy:
	if [[ -z "$${ENV:-}" ]]; then
	    printf '%s\n' "usage: make destroy ENV=env-abc12345" >&2
	    exit 2
	fi
	if [[ -x platform/destroy_env.sh ]]; then
	    bash platform/destroy_env.sh "$$ENV"
	else
	    printf '%s\n' "destroy_env.sh lands in Sprint 2" >&2
	    exit 2
	fi

logs:
	if [[ -z "$${ENV:-}" ]]; then
	    printf '%s\n' "usage: make logs ENV=env-abc12345" >&2
	    exit 2
	fi
	if [[ -f "logs/$$ENV/app.log" ]]; then
	    tail -n 100 -f "logs/$$ENV/app.log"
	else
	    printf '%s\n' "logs/$$ENV/app.log not found" >&2
	    exit 1
	fi

health:
	if compgen -G 'envs/env-*.json' >/dev/null; then
	    for state in envs/env-*.json; do
	        python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("{} {} {}".format(s.get("id"), s.get("name"), s.get("status")))' "$$state"
	    done
	else
	    printf '%s\n' "no active envs"
	fi

simulate:
	if [[ -z "$${ENV:-}" || -z "$${MODE:-}" ]]; then
	    printf '%s\n' "usage: make simulate ENV=env-abc12345 MODE=crash" >&2
	    exit 2
	fi
	if [[ -x platform/simulate_outage.sh ]]; then
	    bash platform/simulate_outage.sh --env "$$ENV" --mode "$$MODE"
	else
	    printf '%s\n' "simulate_outage.sh lands in Sprint 4" >&2
	    exit 2
	fi

clean: down
	clean_runtime() {
	    find envs -mindepth 1 ! -name .gitkeep -exec rm -rf {} +
	    find logs -mindepth 1 ! -name .gitkeep -exec rm -rf {} +
	    find nginx/conf.d -mindepth 1 ! -name .gitkeep ! -name .broken -exec rm -rf {} +
	}
	runtime_leftovers() {
	    find envs -mindepth 1 ! -name .gitkeep -print
	    find logs -mindepth 1 ! -name .gitkeep ! -path logs/archived -print
	    find nginx/conf.d -mindepth 1 ! -name .gitkeep ! -name .broken -print
	}
	clean_as_root_container() {
	    docker run --rm \
	        -e "HOST_UID=$$(id -u)" \
	        -e "HOST_GID=$$(id -g)" \
	        -v "$$(pwd):/workspace" \
	        -w /workspace \
	        --entrypoint sh \
	        nginx:1.27-alpine \
	        -c 'set -eu; \
	            find envs -mindepth 1 ! -name .gitkeep -exec rm -rf {} +; \
	            find logs -mindepth 1 ! -name .gitkeep -exec rm -rf {} +; \
	            find nginx/conf.d -mindepth 1 ! -name .gitkeep ! -name .broken -exec rm -rf {} +; \
	            mkdir -p logs/archived nginx/conf.d/.broken; \
	            chown -R "$$HOST_UID:$$HOST_GID" envs logs nginx/conf.d'
	}
	clean_err="$$(mktemp)"
	if ! clean_runtime 2>"$$clean_err" || runtime_leftovers | grep -q .; then
	    if ! clean_as_root_container; then
	        cat "$$clean_err" >&2
	        rm -f "$$clean_err"
	        printf '%s\n' "ERROR: make clean could not remove runtime files with host user or Docker fallback" >&2
	        exit 1
	    fi
	fi
	if runtime_leftovers | grep -q .; then
	    runtime_leftovers >&2
	    rm -f "$$clean_err"
	    printf '%s\n' "ERROR: make clean left runtime files behind" >&2
	    exit 1
	fi
	rm -f "$$clean_err"
	mkdir -p logs/archived nginx/conf.d/.broken

test-api:
	if command -v newman >/dev/null 2>&1 && [[ "$$(command -v newman)" != /mnt/c/* ]]; then
	    newman run postman/DevOpsSandbox.postman_collection.json \
	        --environment postman/DevOpsSandbox-Local.postman_environment.json
	else
	    docker run --rm --network host \
	        -v "$$(pwd):/workspace" \
	        -w /workspace \
	        node:20-alpine sh -c 'npx --yes newman@6.2.1 run postman/DevOpsSandbox.postman_collection.json --environment postman/DevOpsSandbox-Local.postman_environment.json'
	fi

ship-check:
	pre-commit run --all-files
	bash ci/shellcheck.sh
	$(MAKE) test-api

lint:
	pre-commit run --all-files

format:
	pre-commit run ruff-format --all-files

bundle-evidence:
	bash scripts/capture_evidence.sh
