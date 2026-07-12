#!/usr/bin/env bash
#
# setup-local-env.sh - One-shot local bootstrap for this repo.
#
# Usage:
#   ./scripts/setup-local-env.sh
#
# What it does:
#   1. Checks for the CLI tools this project depends on: docker,
#      docker-compose (or `docker compose`), kubectl, terraform.
#      Missing tools produce a warning, not a hard failure, so you can still
#      bootstrap the parts you have installed (e.g. no local k8s cluster yet).
#   2. Copies .env.example to .env if .env does not already exist. If
#      .env.example itself is missing, a minimal placeholder version is
#      generated from the environment variables docker-compose.yml expects,
#      using non-secret example values - never real credentials.
#   3. Runs `docker-compose up -d` to start api-service, worker-service,
#      web-frontend, postgres, redis, prometheus, grafana, and jaeger.
#   4. Prints next-step commands (URLs, test/deploy scripts).
#
# No secrets are hardcoded by this script: .env.example only ever contains
# placeholder/example values suitable for local development.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Bootstrap this repo for local development:
  - checks for docker, docker-compose, kubectl, terraform
  - creates .env from .env.example if missing
  - runs docker-compose up -d
  - prints next steps

Options:
  -h, --help   Show this help message and exit
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log()  { printf '[setup] %s\n' "$*"; }
warn() { printf '[setup] WARNING: %s\n' "$*" >&2; }
err()  { printf '[setup] ERROR: %s\n' "$*" >&2; }

MISSING_TOOLS=()

check_tool() {
  local tool="$1"
  local hint="$2"
  if command -v "${tool}" >/dev/null 2>&1; then
    log "Found ${tool}: $("${tool}" --version 2>&1 | head -n1)"
  else
    warn "${tool} not found. ${hint}"
    MISSING_TOOLS+=("${tool}")
  fi
}

log "Checking prerequisite CLI tools..."
check_tool docker "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"

# docker-compose may be the standalone binary or the `docker compose` plugin.
if command -v docker-compose >/dev/null 2>&1; then
  log "Found docker-compose: $(docker-compose --version 2>&1 | head -n1)"
  COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  log "Found docker compose plugin: $(docker compose version 2>&1 | head -n1)"
  COMPOSE_CMD="docker compose"
else
  warn "docker-compose (standalone or 'docker compose' plugin) not found."
  MISSING_TOOLS+=("docker-compose")
  COMPOSE_CMD="docker-compose"
fi

check_tool kubectl "Install: https://kubernetes.io/docs/tasks/tools/ (needed for scripts/deploy.sh, scripts/rollback.sh)"
check_tool terraform "Install: https://developer.hashicorp.com/terraform/install (needed for the terraform/ IaC)"

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  warn "Missing tools: ${MISSING_TOOLS[*]}. Continuing anyway - install them for full functionality."
fi

# --- .env bootstrap -----------------------------------------------------
ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE_FILE="${REPO_ROOT}/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
  log ".env already exists, leaving it untouched."
else
  if [[ ! -f "${ENV_EXAMPLE_FILE}" ]]; then
    warn ".env.example not found - generating a minimal placeholder version."
    warn "Review it and replace placeholder values as needed."
    cat > "${ENV_EXAMPLE_FILE}" <<'EOF'
# Example environment configuration for local development.
# Copy to .env and adjust as needed. Never commit .env or real secrets.

ENVIRONMENT=development

# Postgres (matches docker-compose.yml defaults)
POSTGRES_USER=user
POSTGRES_PASSWORD=changeme
POSTGRES_DB=appdb
DATABASE_URL=postgresql://user:changeme@postgres:5432/appdb

# Redis / Celery
REDIS_URL=redis://redis:6379
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/1

# Web frontend
REACT_APP_API_URL=http://localhost:8000
NODE_ENV=development

# Feature flags (see apps/api-service/app.py /api/v1/feature-flags)
FEATURE_NEW_UI=false
FEATURE_ANALYTICS=false
FEATURE_BETA=false

# Grafana admin (local only - change for anything beyond a laptop)
GF_SECURITY_ADMIN_PASSWORD=admin
EOF
  fi
  cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
  log "Created .env from .env.example."
fi

# --- docker-compose up ---------------------------------------------------
if command -v docker >/dev/null 2>&1 && { command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; }; then
  log "Starting local stack with '${COMPOSE_CMD} up -d'..."
  if ! (cd "${REPO_ROOT}" && ${COMPOSE_CMD} up -d); then
    err "docker-compose failed to start the stack. Check the output above."
    exit 1
  fi
else
  warn "Skipping 'docker-compose up -d' - docker and/or docker-compose is not available."
fi

cat <<EOF

--------------------------------------------------------------------
Local environment setup complete (or attempted - see warnings above).

Next steps:
  1. Tail service logs:        ${COMPOSE_CMD} logs -f api-service worker-service
  2. API service:               http://localhost:8000/health  (docs at /docs)
  3. Web frontend:               http://localhost:3000
  4. Prometheus:                 http://localhost:9090
  5. Grafana:                    http://localhost:3001  (admin / see .env)
  6. Jaeger UI:                  http://localhost:16686
  7. Run tests:                  ./scripts/run-tests.sh
  8. Build local images:         ./scripts/build.sh
  9. Deploy to a k8s environment: ./scripts/deploy.sh dev
--------------------------------------------------------------------
EOF
