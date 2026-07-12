#!/usr/bin/env bash
#
# build.sh - Build Docker images for all three microservices locally.
#
# Usage:
#   ./scripts/build.sh [TAG]
#
# Arguments:
#   TAG   Optional image tag applied to all three images. Defaults to "local".
#
# What it does:
#   For each service (api-service, web-frontend, worker-service) this runs
#   `docker build` using the same context/Dockerfile pairing that the
#   `build` job in .github/workflows/ci-cd-pipeline.yml uses
#   (context: apps/<service>, file: docker/Dockerfile.<service>), and tags
#   the result consistently as:
#
#       <IMAGE_PREFIX>/<service>:<TAG>
#
#   IMAGE_PREFIX defaults to "cicd-architect-exam" (a purely local name -
#   nothing is pushed anywhere). In CI, the equivalent image is tagged
#   ghcr.io/<owner>/<repo>/<service>:<ref-or-sha> by docker/metadata-action;
#   this script mirrors that shape locally without requiring registry auth.
#
# Exit codes:
#   0 on success, non-zero if any build fails or prerequisites are missing.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_PREFIX="${IMAGE_PREFIX:-cicd-architect-exam}"
SERVICES=(api-service web-frontend worker-service)

usage() {
  cat <<EOF
Usage: $(basename "$0") [TAG]

Build Docker images for all services (api-service, web-frontend, worker-service).

Arguments:
  TAG             Image tag to apply to all built images (default: local)

Environment variables:
  IMAGE_PREFIX    Local image name prefix (default: cicd-architect-exam)

Examples:
  $(basename "$0")            # builds <prefix>/api-service:local, etc.
  $(basename "$0") v1.2.3     # builds <prefix>/api-service:v1.2.3, etc.

Options:
  -h, --help      Show this help message and exit
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TAG="${1:-local}"

log()  { printf '[build] %s\n' "$*"; }
err()  { printf '[build] ERROR: %s\n' "$*" >&2; }

if ! command -v docker >/dev/null 2>&1; then
  err "docker is not installed or not on PATH. Install Docker Desktop / Docker Engine first."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  err "docker daemon is not reachable. Is Docker running?"
  exit 1
fi

log "Building images with tag '${TAG}' (prefix: ${IMAGE_PREFIX})"

FAILED_SERVICES=()

for service in "${SERVICES[@]}"; do
  context="${REPO_ROOT}/apps/${service}"
  dockerfile="${REPO_ROOT}/docker/Dockerfile.${service}"
  image="${IMAGE_PREFIX}/${service}:${TAG}"

  if [[ ! -d "${context}" ]]; then
    err "Context directory not found: ${context} (skipping ${service})"
    FAILED_SERVICES+=("${service}")
    continue
  fi
  if [[ ! -f "${dockerfile}" ]]; then
    err "Dockerfile not found: ${dockerfile} (skipping ${service})"
    FAILED_SERVICES+=("${service}")
    continue
  fi

  log "Building ${service} -> ${image}"
  if docker build \
      -f "${dockerfile}" \
      -t "${image}" \
      -t "${IMAGE_PREFIX}/${service}:latest" \
      "${context}"; then
    log "Built ${image}"
  else
    err "Build failed for ${service}"
    FAILED_SERVICES+=("${service}")
  fi
done

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
  err "One or more builds failed: ${FAILED_SERVICES[*]}"
  exit 1
fi

log "All images built successfully:"
for service in "${SERVICES[@]}"; do
  log "  ${IMAGE_PREFIX}/${service}:${TAG}"
done
