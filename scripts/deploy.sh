#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${NAMESPACE:-cicd-demo}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-cicd-kubernetes-pipeline}"
CONTAINER_NAME="${CONTAINER_NAME:-web}"
MANIFEST_DIR="${MANIFEST_DIR:-k8s}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-120s}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
DRY_RUN="${DRY_RUN:-false}"
IMAGE="${IMAGE:-}"
KUBECTL="${KUBECTL:-kubectl}"

usage() {
  printf '%s\n' \
    'Usage: deploy.sh --image IMAGE [options]' \
    '' \
    'Apply Kubernetes manifests, update the deployment image, and verify rollout status.' \
    '' \
    'Options:' \
    '  --image IMAGE             Immutable container image to deploy' \
    '  --namespace NAME          Kubernetes namespace (default: cicd-demo)' \
    '  --deployment NAME         Deployment name (default: cicd-kubernetes-pipeline)' \
    '  --container NAME          Container name in the deployment (default: web)' \
    '  --manifest-dir PATH       Directory containing namespace/deployment/service manifests (default: k8s)' \
    '  --timeout DURATION        Rollout timeout passed to kubectl (default: 120s)' \
    '  --context NAME            Kubernetes context to use' \
    '  --dry-run                 Validate apply operations without changing the cluster' \
    '  -h, --help                Show this help message' \
    '' \
    'Environment variables:' \
    '  IMAGE, NAMESPACE, DEPLOYMENT_NAME, CONTAINER_NAME, MANIFEST_DIR,' \
    '  ROLLOUT_TIMEOUT, KUBE_CONTEXT, DRY_RUN, KUBECTL' \
    '' \
    'Exit codes:' \
    '  0  Deployment completed successfully' \
    '  1  Rollout or verification failed' \
    '  2  Invalid configuration, missing dependency, or unsafe image tag'
}

log() {
  printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2"
}

while (( $# > 0 )); do
  case "$1" in
    --image)
      [[ $# -ge 2 ]] || { log ERROR "--image requires a value"; exit 2; }
      IMAGE="$2"
      shift 2
      ;;
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
    --container)
      [[ $# -ge 2 ]] || { log ERROR "--container requires a value"; exit 2; }
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --manifest-dir)
      [[ $# -ge 2 ]] || { log ERROR "--manifest-dir requires a value"; exit 2; }
      MANIFEST_DIR="$2"
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

if [[ -z "$IMAGE" ]]; then
  log ERROR "An immutable image is required. Pass --image ghcr.io/owner/repo:<git-sha>"
  exit 2
fi

case "$IMAGE" in
  *:latest|*:replace-with-git-sha|latest|replace-with-git-sha)
    log ERROR "Refusing unsafe or placeholder image tag: $IMAGE"
    exit 2
    ;;
esac

if [[ "$IMAGE" != *:* ]]; then
  log ERROR "Image must include an explicit immutable tag: $IMAGE"
  exit 2
fi

if [[ "$DRY_RUN" != "true" && "$DRY_RUN" != "false" ]]; then
  log ERROR "DRY_RUN must be true or false"
  exit 2
fi

for manifest in namespace.yaml deployment.yaml service.yaml; do
  if [[ ! -f "$MANIFEST_DIR/$manifest" ]]; then
    log ERROR "Missing required manifest: $MANIFEST_DIR/$manifest"
    exit 2
  fi
done

kubectl_base=("$KUBECTL")
if [[ -n "$KUBE_CONTEXT" ]]; then
  kubectl_base+=(--context "$KUBE_CONTEXT")
fi

apply_args=()
if [[ "$DRY_RUN" == "true" ]]; then
  apply_args+=(--dry-run=server -o yaml)
fi

log INFO "Deployment started"
printf 'Namespace: %s\n' "$NAMESPACE"
printf 'Deployment: %s\n' "$DEPLOYMENT_NAME"
printf 'Container: %s\n' "$CONTAINER_NAME"
printf 'Image: %s\n' "$IMAGE"
printf 'Manifest directory: %s\n' "$MANIFEST_DIR"
printf 'Rollout timeout: %s\n' "$ROLLOUT_TIMEOUT"
printf 'Dry run: %s\n' "$DRY_RUN"

log INFO "Applying Kubernetes manifests"
"${kubectl_base[@]}" apply "${apply_args[@]}" -f "$MANIFEST_DIR/namespace.yaml"
"${kubectl_base[@]}" apply "${apply_args[@]}" -f "$MANIFEST_DIR/deployment.yaml"
"${kubectl_base[@]}" apply "${apply_args[@]}" -f "$MANIFEST_DIR/service.yaml"

if [[ "$DRY_RUN" == "true" ]]; then
  log INFO "Dry-run completed before image update; no cluster resources were changed"
  exit 0
fi

log INFO "Updating deployment image"
"${kubectl_base[@]}" -n "$NAMESPACE" set image \
  "deployment/$DEPLOYMENT_NAME" \
  "$CONTAINER_NAME=$IMAGE" \
  --record=false

log INFO "Waiting for rollout"
if ! "${kubectl_base[@]}" -n "$NAMESPACE" rollout status "deployment/$DEPLOYMENT_NAME" --timeout="$ROLLOUT_TIMEOUT"; then
  log ERROR "Rollout did not complete successfully"
  printf '\nDiagnostic commands:\n'
  printf '%s -n %s describe deployment %s\n' "$KUBECTL" "$NAMESPACE" "$DEPLOYMENT_NAME"
  printf '%s -n %s get pods -l app.kubernetes.io/name=%s -o wide\n' "$KUBECTL" "$NAMESPACE" "$DEPLOYMENT_NAME"
  printf '%s -n %s get events --sort-by=.lastTimestamp\n' "$KUBECTL" "$NAMESPACE"
  exit 1
fi

log INFO "Collecting post-deployment state"
"${kubectl_base[@]}" -n "$NAMESPACE" get deployment "$DEPLOYMENT_NAME" -o wide
"${kubectl_base[@]}" -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=$DEPLOYMENT_NAME" -o wide
"${kubectl_base[@]}" -n "$NAMESPACE" get service "$DEPLOYMENT_NAME"

log INFO "Deployment completed successfully"
