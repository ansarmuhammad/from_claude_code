#!/usr/bin/env bash
#
# rollback.sh - Roll back the microservice deployments in a given environment.
#
# Usage:
#   ./scripts/rollback.sh <dev|staging|production> [REVISION]
#
# Runs:
#   kubectl rollout undo deployment/api-service -n <namespace> [--to-revision=REVISION]
#   kubectl rollout undo deployment/web-frontend -n <namespace> [--to-revision=REVISION]
#   kubectl rollout undo deployment/worker-service -n <namespace> [--to-revision=REVISION]
#
# Namespace mapping matches deploy.sh / the GitHub Actions workflow:
#   dev        -> development
#   staging    -> staging
#   production -> production
#
# Safety:
#   Production rollbacks require an interactive "yes" confirmation unless
#   CONFIRM=yes is set in the environment (useful for scripted/CI use, e.g.
#   an incident-response automation calling this non-interactively).
#
#   NOTE: standard `kubectl rollout undo` operates on a Deployment's own
#   revision history (ReplicaSets) and is the right tool for dev/staging.
#   Production here uses Blue/Green (see scripts/deploy.sh and
#   docs/runbook.md) - if traffic was already switched to "green" and green
#   is broken, the faster rollback is usually re-patching the Service
#   selector back to "blue" rather than `rollout undo`. This script still
#   performs `rollout undo` against the requested deployments so that the
#   underlying Deployment objects (not just the Service selector) are
#   reverted, but check docs/runbook.md for the blue/green-specific
#   incident procedure first.
#
set -euo pipefail

DEPLOYMENTS=(api-service web-frontend worker-service)

usage() {
  cat <<EOF
Usage: $(basename "$0") <dev|staging|production> [REVISION]

Roll back all three service deployments in the given environment.

Arguments:
  dev|staging|production   Target environment (required)
  REVISION                 Optional revision number to roll back to
                            (passed as --to-revision). If omitted, kubectl
                            rolls back to the previous revision.

Environment variables:
  CONFIRM=yes               Skip the interactive confirmation prompt for
                            production rollbacks (use with care, e.g. in
                            automated incident-response tooling).

Options:
  -h, --help                Show this help message and exit

Examples:
  $(basename "$0") dev
  $(basename "$0") staging 4
  $(basename "$0") production
  CONFIRM=yes $(basename "$0") production
EOF
}

log()  { printf '[rollback] %s\n' "$*"; }
err()  { printf '[rollback] ERROR: %s\n' "$*" >&2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
  usage
  [[ $# -eq 0 ]] && exit 1
  exit 0
fi

ENVIRONMENT="$1"
REVISION="${2:-}"

case "${ENVIRONMENT}" in
  dev)
    NAMESPACE="development"
    ;;
  staging)
    NAMESPACE="staging"
    ;;
  production)
    NAMESPACE="production"
    ;;
  *)
    err "Invalid environment '${ENVIRONMENT}'. Must be one of: dev, staging, production."
    usage
    exit 1
    ;;
esac

if ! command -v kubectl >/dev/null 2>&1; then
  err "kubectl is not installed or not on PATH."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  err "Cannot reach a Kubernetes cluster. Check your kubeconfig/context (kubectl config current-context)."
  exit 1
fi

if [[ "${ENVIRONMENT}" == "production" && "${CONFIRM:-}" != "yes" ]]; then
  echo "You are about to roll back PRODUCTION (namespace: ${NAMESPACE})."
  if [[ -n "${REVISION}" ]]; then
    echo "Target revision: ${REVISION}"
  else
    echo "Target revision: previous revision (kubectl default)"
  fi
  read -r -p "Type 'yes' to continue: " CONFIRMATION
  if [[ "${CONFIRMATION}" != "yes" ]]; then
    err "Rollback aborted by user."
    exit 1
  fi
fi

FAILED=()

for deployment in "${DEPLOYMENTS[@]}"; do
  log "Rolling back deployment/${deployment} in namespace ${NAMESPACE}..."
  cmd=(kubectl rollout undo "deployment/${deployment}" -n "${NAMESPACE}")
  if [[ -n "${REVISION}" ]]; then
    cmd+=(--to-revision="${REVISION}")
  fi

  if "${cmd[@]}"; then
    log "Rollback triggered for ${deployment}. Waiting for rollout to settle..."
    if ! kubectl rollout status "deployment/${deployment}" -n "${NAMESPACE}" --timeout=300s; then
      err "Rollback rollout did not stabilize for ${deployment}."
      FAILED+=("${deployment}")
    fi
  else
    err "kubectl rollout undo failed for ${deployment}."
    FAILED+=("${deployment}")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  err "Rollback failed for: ${FAILED[*]}"
  err "See docs/runbook.md for the incident procedure."
  exit 1
fi

log "Rollback complete for environment '${ENVIRONMENT}' (namespace: ${NAMESPACE})."
