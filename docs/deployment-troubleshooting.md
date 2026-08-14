# Deployment Troubleshooting Guide

This guide provides a production-oriented workflow for diagnosing Kubernetes deployment failures in the CI/CD Kubernetes Pipeline project. It is intended for release owners, SREs, and DevOps engineers responding to a failed rollout, unhealthy service, or failed release verification.

## When to Use This Guide

Use this guide when:

- `scripts/deploy.sh` exits with status `1`.
- Kubernetes rollout status times out.
- New pods are not becoming ready.
- The `/healthz` check fails after deployment.
- A service is unreachable after rollout.
- A rollback is being considered but the failure class is unclear.

Do not repeatedly rerun deployment automation without collecting evidence. Repeated retries can replace useful events, obscure the first failing condition, and create avoidable release noise.

## First Five Minutes

Capture release context first:

```bash
git status --short --branch
git rev-parse HEAD
kubectl config current-context
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get svc cicd-kubernetes-pipeline
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

Capture rollout state:

```bash
kubectl -n cicd-demo rollout status deployment/cicd-kubernetes-pipeline --timeout=30s
kubectl -n cicd-demo rollout history deployment/cicd-kubernetes-pipeline
```

If the service is expected to respond locally:

```bash
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -v --max-time 5 http://127.0.0.1:8080/healthz
```

Record the image tag, namespace, deployment name, command output, exit code, and timestamp in release notes or incident notes.

## Troubleshooting Decision Table

| Symptom | Primary Checks | Likely Owner |
| --- | --- | --- |
| `ImagePullBackOff` or `ErrImagePull` | Pod events, image tag, registry auth, image existence. | Release owner or platform owner. |
| `CrashLoopBackOff` | Container logs, previous logs, entrypoint, NGINX config. | Application or image owner. |
| Readiness probe fails | Pod describe, health endpoint, container port, NGINX config. | Application or manifest owner. |
| Rollout times out | Deployment conditions, replica sets, pod state, events. | Release owner. |
| Service is unreachable | Service selector, pod labels, service port, endpoint readiness. | Kubernetes manifest owner. |
| Dry-run fails | YAML schema, missing namespace, invalid manifest fields. | Manifest owner. |
| Rollback fails | Rollout history, deployment existence, RBAC, cluster health. | Release owner or platform owner. |

## Image Pull Failures

Image pull failures usually mean Kubernetes cannot retrieve the requested image from the registry.

Commands:

```bash
kubectl -n cicd-demo describe pod <pod-name>
kubectl -n cicd-demo get events --sort-by=.lastTimestamp | grep -i -E 'pull|image|registry|unauthorized|denied'
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Check:

- Image tag exists in the registry.
- Image tag matches the intended Git SHA.
- The image is not `latest` or `replace-with-git-sha`.
- The cluster has image pull credentials if the registry is private.
- Registry path and repository owner are correct.
- The deployment script was run with the intended `--image`.

Response:

1. Stop the rollout investigation until the image reference is confirmed.
2. Fix the image tag or registry credential issue.
3. Redeploy only after the image is known to exist and be pullable.
4. Roll back if the deployment is causing service impact and the previous revision is known-good.

## CrashLoopBackOff

`CrashLoopBackOff` means the container starts and exits repeatedly. Kubernetes may continue trying, but the release should not be treated as healthy.

Commands:

```bash
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo describe pod <pod-name>
kubectl -n cicd-demo logs <pod-name> -c web
kubectl -n cicd-demo logs <pod-name> -c web --previous
```

Check:

- Container exits because the command or entrypoint fails.
- NGINX config is invalid.
- Files copied by the Dockerfile are missing at runtime.
- Container port does not match the application or NGINX config.
- Security context prevents the process from writing required runtime files.
- Resource limits are too low and the pod was `OOMKilled`.

Response:

1. Preserve logs from current and previous container instances.
2. Compare the failed image with the previous known-good image.
3. Roll back if user-facing impact is confirmed.
4. Add a CI validation or runtime smoke test for the failure mode before retrying.

## Readiness and Liveness Probe Failures

Probe failures can indicate a real application problem or a mismatch between the manifest and runtime.

Commands:

```bash
kubectl -n cicd-demo describe pod <pod-name>
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline -o yaml
kubectl -n cicd-demo logs <pod-name> -c web
```

For local verification:

```bash
kubectl -n cicd-demo port-forward pod/<pod-name> 8080:8080
curl -v --max-time 5 http://127.0.0.1:8080/healthz
```

Check:

- Probe path is `/healthz`.
- Probe port matches the container runtime port.
- NGINX serves the health endpoint.
- Initial delay and timeout are reasonable for startup.
- The pod is listening on the expected port.
- The service forwards to the correct target port.

Response:

1. Confirm whether the application is actually unhealthy or the probe is misconfigured.
2. Roll back if the new image fails a valid readiness check.
3. Fix manifests if the probe does not match the runtime contract.
4. Add CI or deployment dry-run checks if the issue was preventable before runtime.

## Rollout Timeout

A rollout timeout means the deployment did not reach the desired available replica state within the configured timeout.

Commands:

```bash
kubectl -n cicd-demo describe deployment cicd-kubernetes-pipeline
kubectl -n cicd-demo get rs -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

Check:

- New ReplicaSet exists and has desired replicas.
- Pods are pending, crash looping, or failing readiness.
- Old pods remain because `maxUnavailable: 0` protects availability.
- Resource requests cannot be scheduled.
- Node or namespace constraints prevent placement.
- Deployment progress deadline is exceeded.

Response:

1. Identify the pod-level reason before changing timeout values.
2. Avoid increasing timeout unless slow startup is expected and verified.
3. Roll back when the new version cannot become ready and service risk is present.
4. Update deployment strategy or resource requests after root cause is known.

## Service Routing Failures

If pods are ready but the service is unreachable, inspect selectors and ports.

Commands:

```bash
kubectl -n cicd-demo get svc cicd-kubernetes-pipeline -o yaml
kubectl -n cicd-demo get endpoints cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline --show-labels
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -v --max-time 5 http://127.0.0.1:8080/healthz
```

Check:

- Service selector matches pod labels.
- Service port maps to the correct target port.
- Endpoints contain ready pod IPs.
- Pods are ready, not only running.
- Local port-forward target is not already in use.

Response:

1. Fix selector or port mismatch in manifests.
2. Do not rebuild the image when the evidence points to service routing.
3. Add manifest review notes or validation checks if labels drifted.

## Rollback Troubleshooting

Rollback is only useful when a previous deployment revision is available and expected to be safer.

Commands:

```bash
./scripts/rollback.sh --dry-run
kubectl -n cicd-demo rollout history deployment/cicd-kubernetes-pipeline
kubectl -n cicd-demo describe deployment cicd-kubernetes-pipeline
```

If rollback fails:

```bash
kubectl auth can-i patch deployment -n cicd-demo
kubectl auth can-i get deployment -n cicd-demo
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

Check:

- Deployment exists in the expected namespace.
- Rollout history contains a previous revision.
- The operator or workflow has RBAC permission.
- The cluster can schedule or pull the previous revision.
- The rollback target was not also bad.

Response:

1. Preserve rollout history and events.
2. Specify `--to-revision` only when the target revision is known-good.
3. Escalate to the platform owner if RBAC or cluster health blocks rollback.
4. After rollback, verify `/healthz` and record restored image or revision.

## Evidence Checklist

Capture these fields for failed deployments:

| Field | Example |
| --- | --- |
| Git SHA | `1a2b3c4` |
| Image | `ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:1a2b3c4` |
| Namespace | `cicd-demo` |
| Deployment | `cicd-kubernetes-pipeline` |
| Failing command | `./scripts/deploy.sh --image ...` |
| Exit code | `1` |
| Pod status | `ImagePullBackOff`, `CrashLoopBackOff`, `Running`, `Pending` |
| Health check | `/healthz failed` |
| Rollback decision | `rollback executed` or `rollback not applicable` |
| Follow-up | Test, runbook, manifest, or pipeline improvement |

## Preventive Follow-Up

After troubleshooting, create a follow-up for the first missing control that would have caught the issue earlier.

Examples:

- Add image existence verification before deployment.
- Add manifest validation to CI.
- Add an NGINX config test to the Docker build workflow.
- Add a smoke test after local container build.
- Add service selector checks to deployment review.
- Add release checklist steps for registry and cluster credentials.
- Tighten rollback documentation for revision selection.

Troubleshooting should reduce the chance of seeing the same failure again.
