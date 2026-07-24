#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${NAMESPACE:-cicd-demo}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-cicd-kubernetes-pipeline}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-120s}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
TO_REVISION="${TO_REVISION:-}"
DRY_RUN="${DRY_RUN:-false}"
KUBECTL="${KUBECTL:-kubectl}"

usage() {
  printf '%s\n' \
    'Usage: rollback.sh [options]' \
    '' \
    'Roll back a Kubernetes deployment and verify rollout status.' \
    '' \
    'Options:' \
    '  --namespace NAME       Kubernetes namespace (default: cicd-demo)' \
    '  --deployment NAME      Deployment name (default: cicd-kubernetes-pipeline)' \
    '  --to-revision NUMBER   Roll back to a specific deployment revision' \
    '  --timeout DURATION     Rollout timeout passed to kubectl (default: 120s)' \
    '  --context NAME         Kubernetes context to use' \
    '  --dry-run              Print rollout history without changing the cluster' \
    '  -h, --help             Show this help message' \
    '' \
    'Environment variables:' \
    '  NAMESPACE, DEPLOYMENT_NAME, TO_REVISION, ROLLOUT_TIMEOUT, KUBE_CONTEXT, DRY_RUN, KUBECTL' \
    '' \
    'Exit codes:' \
    '  0  Rollback completed successfully or dry-run completed' \
    '  1  Rollback or verification failed' \
    '  2  Invalid configuration or missing dependency'
}

log() {
  printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2"
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

while (( $# > 0 )); do
  case "$1" in
    --namespace)
      [[ $# -ge 2 ]] || { log ERROR "--namespace requires a value"; exit 2; }
      NAMESPACE="$2"
      shift 2
      ;;
    --deployment)
      [[ $# -ge 2 ]] || { log ERROR "--deployment requires a value"; exit 2; }
      DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    --to-revision)
      [[ $# -ge 2 ]] || { log ERROR "--to-revision requires a value"; exit 2; }
      TO_REVISION="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { log ERROR "--timeout requires a value"; exit 2; }
      ROLLOUT_TIMEOUT="$2"
      shift 2
      ;;
    --context)
      [[ $# -ge 2 ]] || { log ERROR "--context requires a value"; exit 2; }
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log ERROR "Unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
  log ERROR "Required command is unavailable: $KUBECTL"
  exit 2
fi

if [[ "$DRY_RUN" != "true" && "$DRY_RUN" != "false" ]]; then
  log ERROR "DRY_RUN must be true or false"
  exit 2
fi

if [[ -n "$TO_REVISION" ]] && ! is_positive_integer "$TO_REVISION"; then
  log ERROR "--to-revision must be a positive integer"
  exit 2
fi

kubectl_base=("$KUBECTL")
if [[ -n "$KUBE_CONTEXT" ]]; then
  kubectl_base+=(--context "$KUBE_CONTEXT")
fi

log INFO "Rollback request started"
printf 'Namespace: %s\n' "$NAMESPACE"
printf 'Deployment: %s\n' "$DEPLOYMENT_NAME"
printf 'Target revision: %s\n' "${TO_REVISION:-previous}"
printf 'Rollout timeout: %s\n' "$ROLLOUT_TIMEOUT"
printf 'Dry run: %s\n' "$DRY_RUN"

log INFO "Current rollout history"
if ! "${kubectl_base[@]}" -n "$NAMESPACE" rollout history "deployment/$DEPLOYMENT_NAME"; then
  log ERROR "Unable to read rollout history"
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log INFO "Dry-run completed; no rollback was performed"
  exit 0
fi

rollback_args=()
if [[ -n "$TO_REVISION" ]]; then
  rollback_args+=(--to-revision="$TO_REVISION")
fi

log INFO "Executing rollback"
if ! "${kubectl_base[@]}" -n "$NAMESPACE" rollout undo "deployment/$DEPLOYMENT_NAME" "${rollback_args[@]}"; then
  log ERROR "Rollback command failed"
  exit 1
fi

log INFO "Waiting for rollback rollout"
if ! "${kubectl_base[@]}" -n "$NAMESPACE" rollout status "deployment/$DEPLOYMENT_NAME" --timeout="$ROLLOUT_TIMEOUT"; then
  log ERROR "Rollback rollout did not complete successfully"
  printf '\nDiagnostic commands:\n'
  printf '%s -n %s describe deployment %s\n' "$KUBECTL" "$NAMESPACE" "$DEPLOYMENT_NAME"
  printf '%s -n %s get pods -l app.kubernetes.io/name=%s -o wide\n' "$KUBECTL" "$NAMESPACE" "$DEPLOYMENT_NAME"
  printf '%s -n %s get events --sort-by=.lastTimestamp\n' "$KUBECTL" "$NAMESPACE"
  exit 1
fi

log INFO "Collecting post-rollback state"
"${kubectl_base[@]}" -n "$NAMESPACE" get deployment "$DEPLOYMENT_NAME" -o wide
"${kubectl_base[@]}" -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=$DEPLOYMENT_NAME" -o wide
"${kubectl_base[@]}" -n "$NAMESPACE" rollout history "deployment/$DEPLOYMENT_NAME"

log INFO "Rollback completed successfully"
