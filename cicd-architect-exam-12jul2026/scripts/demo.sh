#!/usr/bin/env bash
#
# demo.sh - Serve the live demo dashboard (demo/index.html) and open it in a browser.
#
# Usage:
#   ./scripts/demo.sh [port]
#
# The dashboard talks directly to the services started by `docker-compose up -d`
# (api-service:8000, worker-service:9100, prometheus:9090, grafana:3001,
# jaeger:16686, web-frontend:3000). Make sure that stack is running first.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORT="${1:-8090}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $(basename "$0") [port]"
  echo "Serves demo/index.html at http://localhost:<port> (default 8090)."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[demo] ERROR: python3 not found (needed to serve the dashboard)." >&2
  exit 1
fi

URL="http://localhost:${PORT}"
echo "[demo] Serving demo dashboard at ${URL}"
echo "[demo] Make sure the stack is running first: docker-compose up -d"

if command -v open >/dev/null 2>&1; then
  ( sleep 1 && open "${URL}" ) &
elif command -v xdg-open >/dev/null 2>&1; then
  ( sleep 1 && xdg-open "${URL}" ) &
fi

cd "${REPO_ROOT}/demo" && exec python3 -m http.server "${PORT}"
