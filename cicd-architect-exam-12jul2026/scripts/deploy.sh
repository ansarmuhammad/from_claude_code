#!/usr/bin/env bash
#
# deploy.sh - Deploy the three microservices to a Kubernetes environment.
#
# Usage:
#   ./scripts/deploy.sh <dev|staging|production>
#
# This mirrors the deploy-dev / deploy-staging / deploy-production jobs in
# .github/workflows/ci-cd-pipeline.yml:
#
#   dev         kubectl apply -k kubernetes/overlays/dev/          (ns: development)
#   staging     kubectl apply -k kubernetes/overlays/staging/      (ns: staging)
#   production  Blue/Green two-step (ns: production), see below.
#
# Blue/Green (production) - mirrors the "Blue-Green Deployment" step in the
# workflow's deploy-production job:
#   1. Apply the "green" overlay (the new version) alongside the running
#      "blue" version.
#   2. Wait for green pods to become Ready.
#   3. Patch the Service selector to point traffic at version=green.
#   4. Pause briefly to allow verification (smoke tests / dashboards) before
#      moving on.
#   5. Re-apply the "blue" overlay so that "blue" is refreshed and ready to
#      receive the *next* release (blue/green flips roles each deploy -
#      whichever color is idle gets updated first next time).
#
#   NOTE: this script does not automatically roll back if the post-switch
#   pause reveals problems. In the real pipeline that decision point is where
#   a human (or automated SLO check) would decide to patch the selector back
#   to "blue" - see docs/runbook.md for the manual rollback procedure and
#   scripts/rollback.sh for standard (non blue/green) rollbacks.
#
# Flags:
#   -h, --help   Show this help message and exit
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
GREEN_WAIT_TIMEOUT="${GREEN_WAIT_TIMEOUT:-300s}"
POST_SWITCH_PAUSE_SECONDS="${POST_SWITCH_PAUSE_SECONDS:-30}"

DEPLOYMENTS=(api-service web-frontend worker-service)

usage() {
  cat <<EOF
Usage: $(basename "$0") <dev|staging|production>

Deploy the api-service, web-frontend, and worker-service to the given
Kubernetes environment using the same kustomize overlays as GitHub Actions.

Arguments:
  dev|staging|production   Target environment (required)

Environment variables:
  ROLLOUT_TIMEOUT           Timeout passed to 'kubectl rollout status' (default: 300s)
  GREEN_WAIT_TIMEOUT        Timeout for green pods to become Ready in production (default: 300s)
  POST_SWITCH_PAUSE_SECONDS Pause after switching traffic to green, in seconds (default: 30)

Options:
  -h, --help                Show this help message and exit

Examples:
  $(basename "$0") dev
  $(basename "$0") staging
  $(basename "$0") production
EOF
}

log()  { printf '[deploy] %s\n' "$*"; }
err()  { printf '[deploy] ERROR: %s\n' "$*" >&2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
  usage
  [[ $# -eq 0 ]] && exit 1
  exit 0
fi

ENVIRONMENT="$1"

case "${ENVIRONMENT}" in
  dev)
    OVERLAY_PATH="kubernetes/overlays/dev/"
    NAMESPACE="development"
    ;;
  staging)
    OVERLAY_PATH="kubernetes/overlays/staging/"
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

rollout_check() {
  local deployment="$1"
  local namespace="$2"
  log "Checking rollout status for deployment/${deployment} in namespace ${namespace}..."
  if ! kubectl rollout status "deployment/${deployment}" -n "${namespace}" --timeout="${ROLLOUT_TIMEOUT}"; then
    err "Rollout did not complete for deployment/${deployment} in namespace ${namespace}."
    err "Investigate with: kubectl describe deployment/${deployment} -n ${namespace}"
    err "                   kubectl logs -l app=${deployment} -n ${namespace} --tail=100"
    exit 1
  fi
}

deploy_dev_or_staging() {
  log "Applying kustomize overlay: ${OVERLAY_PATH} (namespace: ${NAMESPACE})"
  if ! kubectl apply -k "${REPO_ROOT}/${OVERLAY_PATH}"; then
    err "kubectl apply failed for ${OVERLAY_PATH}"
    exit 1
  fi

  for deployment in "${DEPLOYMENTS[@]}"; do
    rollout_check "${deployment}" "${NAMESPACE}"
  done
}

deploy_production_blue_green() {
  log "Starting Blue/Green deployment to production (namespace: ${NAMESPACE})"

  log "Step 1/4: Applying green overlay (kubernetes/overlays/production/green/)"
  if ! kubectl apply -k "${REPO_ROOT}/kubernetes/overlays/production/green/"; then
    err "kubectl apply failed for production/green overlay."
    exit 1
  fi

  log "Step 2/4: Waiting up to ${GREEN_WAIT_TIMEOUT} for green pods to become Ready"
  if ! kubectl wait --for=condition=ready pod \
      -l app=api-service,version=green \
      -n "${NAMESPACE}" --timeout="${GREEN_WAIT_TIMEOUT}"; then
    err "Green pods did not become ready in time. Aborting before traffic switch."
    err "Green pods are left running for inspection: kubectl get pods -l version=green -n ${NAMESPACE}"
    exit 1
  fi

  log "Step 3/4: Switching Service traffic to version=green"
  if ! kubectl patch service api-service -n "${NAMESPACE}" \
      -p '{"spec":{"selector":{"version":"green"}}}'; then
    err "Failed to patch api-service Service selector to green."
    exit 1
  fi

  log "Pausing ${POST_SWITCH_PAUSE_SECONDS}s to allow verification (smoke tests, dashboards, alerts)..."
  sleep "${POST_SWITCH_PAUSE_SECONDS}"

  log "Step 4/4: Re-applying blue overlay to refresh the idle (blue) side for the next release"
  if ! kubectl apply -k "${REPO_ROOT}/kubernetes/overlays/production/blue/"; then
    err "kubectl apply failed for production/blue overlay. Traffic is currently on GREEN."
    err "Blue was not refreshed - this does not affect current traffic, but fix before next deploy."
    exit 1
  fi

  for deployment in "${DEPLOYMENTS[@]}"; do
    rollout_check "${deployment}" "${NAMESPACE}"
  done

  log "Blue/Green deployment to production complete. Traffic is on GREEN."
  log "If issues are found post-deploy, see docs/runbook.md and scripts/rollback.sh."
}

case "${ENVIRONMENT}" in
  dev|staging)
    deploy_dev_or_staging
    ;;
  production)
    deploy_production_blue_green
    ;;
esac

log "Deployment to ${ENVIRONMENT} finished successfully."
