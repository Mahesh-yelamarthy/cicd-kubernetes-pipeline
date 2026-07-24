# Deployment Automation

This document describes the Day 15 deployment automation for the CI/CD Kubernetes Pipeline.

The deployment script is intentionally small and explicit. It applies the Kubernetes manifests, sets an immutable image tag on the deployment, waits for rollout completion, and prints post-deployment state for operators.

## Script

```text
scripts/deploy.sh
```

## Deployment Contract

The script expects:

- `kubectl` installed on the runner or operator workstation.
- Access to the target Kubernetes context.
- Manifests in `k8s/namespace.yaml`, `k8s/deployment.yaml`, and `k8s/service.yaml`.
- An immutable image tag, normally derived from the Git commit SHA.

The script refuses `latest`, `replace-with-git-sha`, and untagged images because those tags make deployments harder to audit and roll back.

## Example

```bash
./scripts/deploy.sh \
  --image ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:1a2b3c4d5e6f \
  --namespace cicd-demo \
  --timeout 120s
```

For cluster-side validation without changing resources:

```bash
./scripts/deploy.sh \
  --image ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:1a2b3c4d5e6f \
  --dry-run
```

## Deployment Flow

```text
Validate inputs
    |
    v
Apply namespace, deployment, and service manifests
    |
    v
Set deployment image to immutable tag
    |
    v
Wait for rollout status
    |
    v
Print deployment, pod, and service state
```

## Exit Codes

| Exit code | Meaning | Operator action |
| --- | --- | --- |
| `0` | Deployment or dry-run completed successfully. | Record the release and continue verification. |
| `1` | Rollout or verification failed. | Inspect deployment, pods, and events before retrying. |
| `2` | Invalid input, missing manifest, missing `kubectl`, or unsafe image tag. | Fix configuration before running again. |

## Operational Checks

After a successful deployment:

```bash
kubectl -n cicd-demo rollout status deployment/cicd-kubernetes-pipeline --timeout=120s
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get svc cicd-kubernetes-pipeline
```

For local service verification:

```bash
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -fsS http://127.0.0.1:8080/healthz
```

Expected response:

```text
ok
```

## Failure Triage

If rollout status fails:

1. Confirm the image exists in the registry.
2. Confirm the cluster can pull from the registry.
3. Inspect deployment conditions.
4. Inspect pod status, events, and container logs.
5. Confirm readiness and liveness probes match the application.
6. Roll back only after understanding whether the failure is image, config, cluster, or dependency related.

Useful commands:

```bash
kubectl -n cicd-demo describe deployment cicd-kubernetes-pipeline
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo describe pod <pod-name>
kubectl -n cicd-demo logs <pod-name> -c web
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

If rollback is the correct mitigation, use:

```bash
./scripts/rollback.sh \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --timeout 120s
```

## GitHub Actions Integration

This script is suitable for a future deployment workflow after image publishing is added.

The workflow should:

- Build and push an image tagged with the Git SHA.
- Authenticate to the target cluster using a short-lived credential.
- Run `scripts/deploy.sh --image ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:${GITHUB_SHA}`.
- Store deployment logs as workflow output.
- Stop the pipeline if rollout verification fails.
- Call rollback automation only from an approved recovery workflow or manual incident response step.

Cluster credentials, registry tokens, and kubeconfig data must be stored in GitHub Actions secrets or an approved secret manager. They must not be committed to this repository.
