# Rollback Automation

This document describes the Day 18 rollback automation for the CI/CD Kubernetes Pipeline.

Rollback automation exists to recover safely from failed or harmful deployments. Use it after a responder confirms that rollback is the correct mitigation and that the previous revision is expected to be safer.

## Script

```text
scripts/rollback.sh
```

## Rollback Contract

The script expects:

- `kubectl` installed on the runner or operator workstation.
- Access to the target Kubernetes context.
- An existing Kubernetes deployment with rollout history.
- A responder who has confirmed rollback is the desired mitigation.

By default, the script rolls back to the previous deployment revision. A specific revision can be supplied with `--to-revision`.

## Examples

Preview rollout history without changing the cluster:

```bash
./scripts/rollback.sh --dry-run
```

Roll back to the previous revision:

```bash
./scripts/rollback.sh \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --timeout 120s
```

Roll back to a specific revision:

```bash
./scripts/rollback.sh \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --to-revision 3 \
  --timeout 120s
```

## Rollback Flow

```text
Validate inputs
    |
    v
Read rollout history
    |
    v
Run kubectl rollout undo
    |
    v
Wait for rollout status
    |
    v
Print deployment, pod, and rollout history state
```

## Exit Codes

| Exit code | Meaning | Operator action |
| --- | --- | --- |
| `0` | Rollback or dry-run completed successfully. | Continue service health verification. |
| `1` | Rollback command or rollout verification failed. | Inspect deployment, pods, events, and cluster health. |
| `2` | Invalid input or missing `kubectl`. | Fix local configuration before retrying. |

## When to Roll Back

Rollback is appropriate when:

- A deployment causes failed readiness or liveness probes.
- Error rate, latency, or user impact clearly starts after a release.
- The new image has a known bad configuration or dependency issue.
- The previous revision is known and expected to be safe.

Rollback may not help when the issue is caused by:

- Cluster capacity shortage.
- Node failure.
- Registry outage.
- External dependency outage.
- Shared configuration or secret changes outside the deployment revision.

## Verification

After rollback:

```bash
kubectl -n cicd-demo rollout status deployment/cicd-kubernetes-pipeline --timeout=120s
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

Then verify the service endpoint:

```bash
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -fsS http://127.0.0.1:8080/healthz
```

Expected response:

```text
ok
```

## Post-Rollback Actions

After service recovery:

1. Record the failed image tag and rollback revision.
2. Link the rollback to the deployment or incident ticket.
3. Preserve logs from the failed pods when possible.
4. Identify whether the failure escaped CI validation.
5. Add a test, check, or runbook update that would catch the failure earlier.

Do not delete the failed image or deployment history until the incident review is complete.
