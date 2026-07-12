#!/usr/bin/env bash
#
# run-tests.sh - Run the test suite locally, mirroring the CI test layout.
#
# Usage:
#   ./scripts/run-tests.sh [--integration] [--e2e] [--perf] [--all]
#
# Always runs (mirrors the "unit-tests" matrix job in
# .github/workflows/ci-cd-pipeline.yml):
#   - apps/api-service:    pytest test_*.py --cov=. ...
#   - apps/worker-service: pytest test_*.py --cov=. ...
#
# Optional, mirrors later CI jobs:
#   --integration   apps needing postgres+redis running; runs
#                   `pytest tests/integration/ -v`
#                   (the workflow's integration-tests job additionally spins
#                   up docker/docker-compose.test.yml - this script assumes
#                   you already have postgres/redis available, e.g. via
#                   `docker-compose up -d` or ./scripts/setup-local-env.sh)
#   --e2e           runs Playwright tests: `playwright test tests/e2e/`
#                   (mirrors the deploy-staging job's "Run E2E tests" step)
#   --perf          runs k6 load test: `k6 run tests/performance/load-test.js`
#                   (mirrors the performance-test job's k6-action step)
#   --all           shorthand for --integration --e2e --perf
#
# Exit codes:
#   0 if every requested test phase passed, non-zero otherwise. Unit tests
#   for both services always run first (fail-fast) before any optional
#   phase is attempted.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RUN_INTEGRATION=false
RUN_E2E=false
RUN_PERF=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--integration] [--e2e] [--perf] [--all]

Runs unit tests for api-service and worker-service (always). Optionally
also runs integration, e2e, and/or performance tests.

Options:
  --integration   Run tests/integration/ with pytest (requires postgres+redis
                   reachable, e.g. via docker-compose up -d)
  --e2e            Run tests/e2e/ with Playwright (requires the app stack
                   running and reachable)
  --perf           Run tests/performance/load-test.js with k6
  --all            Equivalent to --integration --e2e --perf
  -h, --help       Show this help message and exit

Examples:
  $(basename "$0")                    # unit tests only
  $(basename "$0") --integration       # unit + integration
  $(basename "$0") --all               # unit + integration + e2e + perf
EOF
}

for arg in "$@"; do
  case "${arg}" in
    --integration) RUN_INTEGRATION=true ;;
    --e2e) RUN_E2E=true ;;
    --perf) RUN_PERF=true ;;
    --all) RUN_INTEGRATION=true; RUN_E2E=true; RUN_PERF=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf '[run-tests] ERROR: Unknown option: %s\n' "${arg}" >&2
      usage
      exit 1
      ;;
  esac
done

log()  { printf '[run-tests] %s\n' "$*"; }
err()  { printf '[run-tests] ERROR: %s\n' "$*" >&2; }

if ! command -v python3 >/dev/null 2>&1; then
  err "python3 is not installed or not on PATH."
  exit 1
fi

run_unit_tests_for_service() {
  local service="$1"
  local dir="${REPO_ROOT}/apps/${service}"

  if [[ ! -d "${dir}" ]]; then
    err "Service directory not found: ${dir}"
    return 1
  fi

  log "Running unit tests for ${service}..."
  (
    cd "${dir}"
    if ! command -v pytest >/dev/null 2>&1 && ! python3 -m pytest --version >/dev/null 2>&1; then
      err "pytest is not installed. Run: pip install -r requirements.txt pytest pytest-cov pytest-asyncio"
      exit 1
    fi
    python3 -m pytest test_*.py \
      --cov=. \
      --cov-report=term \
      --junitxml=junit.xml
  )
}

log "=== Unit tests (api-service, worker-service) ==="
FAILED_PHASES=()

if ! run_unit_tests_for_service "api-service"; then
  FAILED_PHASES+=("unit:api-service")
fi

if ! run_unit_tests_for_service "worker-service"; then
  FAILED_PHASES+=("unit:worker-service")
fi

if [[ ${#FAILED_PHASES[@]} -gt 0 ]]; then
  err "Unit tests failed: ${FAILED_PHASES[*]}. Stopping before optional phases (fail-fast)."
  exit 1
fi
log "Unit tests passed for both services."

if [[ "${RUN_INTEGRATION}" == "true" ]]; then
  log "=== Integration tests (tests/integration/) ==="
  if [[ ! -d "${REPO_ROOT}/tests/integration" ]]; then
    err "tests/integration/ not found - nothing to run."
    FAILED_PHASES+=("integration")
  elif ! python3 -m pytest --version >/dev/null 2>&1; then
    err "pytest is not installed. Run: pip install pytest pytest-asyncio httpx"
    FAILED_PHASES+=("integration")
  else
    if ! (cd "${REPO_ROOT}" && python3 -m pytest tests/integration/ -v); then
      err "Integration tests failed."
      FAILED_PHASES+=("integration")
    else
      log "Integration tests passed."
    fi
  fi
fi

if [[ "${RUN_E2E}" == "true" ]]; then
  log "=== E2E tests (tests/e2e/, Playwright) ==="
  if [[ ! -d "${REPO_ROOT}/tests/e2e" ]]; then
    err "tests/e2e/ not found - nothing to run."
    FAILED_PHASES+=("e2e")
  elif ! command -v playwright >/dev/null 2>&1 && ! npx --no-install playwright --version >/dev/null 2>&1; then
    err "playwright is not installed. Run: npm install -g playwright && playwright install"
    FAILED_PHASES+=("e2e")
  else
    if command -v playwright >/dev/null 2>&1; then
      PLAYWRIGHT_CMD="playwright"
    else
      PLAYWRIGHT_CMD="npx playwright"
    fi
    if ! (cd "${REPO_ROOT}" && ${PLAYWRIGHT_CMD} test tests/e2e/); then
      err "E2E tests failed."
      FAILED_PHASES+=("e2e")
    else
      log "E2E tests passed."
    fi
  fi
fi

if [[ "${RUN_PERF}" == "true" ]]; then
  log "=== Performance tests (tests/performance/load-test.js, k6) ==="
  if [[ ! -f "${REPO_ROOT}/tests/performance/load-test.js" ]]; then
    err "tests/performance/load-test.js not found - nothing to run."
    FAILED_PHASES+=("perf")
  elif ! command -v k6 >/dev/null 2>&1; then
    err "k6 is not installed. Install: https://k6.io/docs/get-started/installation/"
    FAILED_PHASES+=("perf")
  else
    if ! (cd "${REPO_ROOT}" && k6 run tests/performance/load-test.js); then
      err "Performance tests failed (or thresholds breached)."
      FAILED_PHASES+=("perf")
    else
      log "Performance tests passed."
    fi
  fi
fi

if [[ ${#FAILED_PHASES[@]} -gt 0 ]]; then
  err "The following phases failed or could not run: ${FAILED_PHASES[*]}"
  exit 1
fi

log "All requested test phases passed."
