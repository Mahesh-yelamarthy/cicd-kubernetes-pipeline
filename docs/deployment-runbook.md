# Deployment Runbook

This runbook describes how to deploy the CI/CD Kubernetes Pipeline demo workload to Kubernetes, verify the rollout, and decide whether to roll back. It is written for an operator or release owner executing a controlled production-style deployment.

## Scope

Use this runbook for:

- Deploying a known immutable image tag.
- Verifying Kubernetes rollout status.
- Checking pod, service, and application health.
- Capturing release evidence.
- Initiating rollback when deployment safety checks fail.

This runbook assumes the image was already built and validated by CI. It does not replace application testing, security review, or production approval.

## Required Inputs

| Input | Example | Notes |
| --- | --- | --- |
| Image | `ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:<git-sha>` | Must include an immutable tag. Do not use `latest`. |
| Namespace | `cicd-demo` | Must match the target Kubernetes environment. |
| Deployment | `cicd-kubernetes-pipeline` | Must match `k8s/deployment.yaml`. |
| Container | `web` | Must match the container name in the deployment. |
| Timeout | `120s` | Increase only when rollout behavior is understood. |
| Kubernetes context | `staging` or `production` | Optional but recommended for explicit targeting. |

## Pre-Deployment Checks

Confirm the working tree and intended image:

```bash
git status --short --branch
git rev-parse --short HEAD
```

Confirm the deployment artifact uses an immutable tag:

```bash
IMAGE="ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:$(git rev-parse --short HEAD)"
printf '%s\n' "$IMAGE"
```

Reject the deployment if the image tag is:

- Empty
- Untagged
- `latest`
- `replace-with-git-sha`
- Not associated with the intended commit

Confirm Kubernetes access and target context:

```bash
kubectl config current-context
kubectl get namespace cicd-demo
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline
```

Confirm the release owner has reviewed:

- CI build result
- Image tag
- Target namespace
- Expected user impact
- Rollback path
- Monitoring or manual verification plan

## Dry Run

Use server-side dry-run before making cluster changes:

```bash
./scripts/deploy.sh \
  --image "$IMAGE" \
  --namespace cicd-demo \
  --timeout 120s \
  --dry-run
```

Expected result:

- Namespace, deployment, and service manifests validate successfully.
- No cluster resources are changed.
- The script exits with status `0`.

If dry-run fails, stop the release and fix the configuration before retrying.

## Deployment Procedure

Run the deployment:

```bash
./scripts/deploy.sh \
  --image "$IMAGE" \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --container web \
  --timeout 120s
```

The script performs these actions:

1. Validates required inputs and image tag safety.
2. Applies namespace, deployment, and service manifests.
3. Updates the deployment image.
4. Waits for Kubernetes rollout status.
5. Prints deployment, pod, and service state.

Do not open a second deployment for the same workload while a rollout is still in progress.

## Rollout Verification

After the script completes, verify rollout state:

```bash
kubectl -n cicd-demo rollout status deployment/cicd-kubernetes-pipeline --timeout=120s
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get svc cicd-kubernetes-pipeline
```

Verify the application health endpoint:

```bash
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -fsS http://127.0.0.1:8080/healthz
```

Expected response:

```text
ok
```

Review recent Kubernetes events:

```bash
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

A deployment is successful only when:

- Rollout status completes.
- Desired replicas are available.
- Pods are ready.
- The service exists.
- The `/healthz` endpoint succeeds.
- No critical deployment events explain hidden instability.

## Failure Triage

If rollout fails or times out, collect evidence before retrying:

```bash
kubectl -n cicd-demo describe deployment cicd-kubernetes-pipeline
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo describe pod <pod-name>
kubectl -n cicd-demo logs <pod-name> -c web
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

Common failure classes:

| Symptom | Likely Cause | First Response |
| --- | --- | --- |
| `ImagePullBackOff` | Image tag missing, registry auth failure, or wrong registry path. | Confirm image exists and cluster can pull it. |
| `CrashLoopBackOff` | Container starts and exits repeatedly. | Check container logs and entrypoint behavior. |
| Readiness probe failure | Application is running but not ready. | Confirm `/healthz`, port, and NGINX configuration. |
| Rollout timeout | Pods did not become available in time. | Inspect deployment conditions, pods, and events. |
| Service check fails | Service selector, port, or pod readiness mismatch. | Compare service selector with pod labels and container ports. |

Do not keep re-running the deployment command without understanding the failure class. Repeated retries can hide the original evidence and increase incident noise.

## Rollback Decision

Roll back when:

- The new image fails rollout verification.
- The health endpoint fails after rollout.
- The release causes confirmed user-facing impact.
- Error rate or latency rises materially after deployment.
- The previous revision is known and expected to be safer.

Do not roll back as the first response when the issue is clearly unrelated to the release, such as a node outage, registry outage, or external dependency failure.

Rollback command:

```bash
./scripts/rollback.sh \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --timeout 120s
```

After rollback, repeat the rollout and endpoint verification steps.

## Release Evidence

Record the following after every deployment:

| Field | Example |
| --- | --- |
| Release owner | `mahesh` |
| Git SHA | `1a2b3c4` |
| Image | `ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:1a2b3c4` |
| Namespace | `cicd-demo` |
| Deployment time | `2026-08-09T01:45:00Z` |
| Rollout result | `success` or `failed` |
| Health check result | `/healthz ok` |
| Rollback needed | `yes` or `no` |
| Follow-up | Link to issue or incident notes |

Example release note:

```text
Release: cicd-kubernetes-pipeline
Image: ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:1a2b3c4
Namespace: cicd-demo
Result: rollout succeeded, /healthz returned ok
Evidence: deployment available=2/2, service present, no critical events
Rollback: not required
```

## Post-Deployment Follow-Up

After a successful release:

1. Confirm the release is visible in the deployment history.
2. Confirm monitoring or manual smoke checks remain healthy.
3. Record the deployed image and Git SHA.
4. Keep deployment logs with the release evidence.
5. Open follow-up work for any warning signs found during verification.

After a failed release:

1. Preserve pod logs and Kubernetes events.
2. Record the failed image tag.
3. Roll back when release-related impact is confirmed.
4. Identify the missing validation that allowed the issue through.
5. Add a test, script check, or runbook update before retrying.
