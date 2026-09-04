# Release Checklist

This checklist defines the release readiness, deployment, verification, rollback, and follow-up controls for the CI/CD Kubernetes Pipeline project. It is intended for release owners who need a repeatable production-style process, not just a successful script execution.

## Scope

Use this checklist before and after running:

```text
scripts/deploy.sh
```

Use it with:

- `docs/release-strategy.md`
- `docs/deployment-runbook.md`
- `docs/deployment-troubleshooting.md`
- `docs/rollback-automation.md`
- `docs/production-readiness-review.md`

## Release Inputs

| Input | Required Value |
| --- | --- |
| Git SHA | Exact commit intended for release. |
| Image | Immutable image tag associated with the Git SHA. |
| Environment | Explicit Kubernetes namespace and context. |
| Release owner | Person accountable for execution and verification. |
| Rollback path | Previous known-good revision or rollback command. |
| Verification plan | Rollout status, pod readiness, service, and `/healthz`. |

## Pre-Release Checklist

Complete these before deployment:

- [ ] Working tree is clean.
- [ ] Target Git SHA is recorded.
- [ ] CI build workflow passed for the target commit.
- [ ] Container image exists in the registry.
- [ ] Image tag is immutable and not `latest`.
- [ ] Kubernetes context is explicit and correct.
- [ ] Target namespace is correct.
- [ ] Deployment name is correct.
- [ ] Required manifests exist under `k8s/`.
- [ ] Rollback command and expected previous revision are understood.
- [ ] Release owner is available during rollout.
- [ ] Service owner or reviewer is available if application behavior must be verified.

Suggested commands:

```bash
git status --short --branch
git rev-parse HEAD
kubectl config current-context
kubectl get namespace cicd-demo
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline
```

## Artifact Checklist

Confirm artifact integrity:

- [ ] Image name matches the repository and workload.
- [ ] Image tag matches the intended Git SHA.
- [ ] Docker build used the expected `Dockerfile`.
- [ ] Runtime port and Kubernetes probe port still match.
- [ ] NGINX config is included in the image.
- [ ] Health endpoint is expected to return `ok`.

Expected image format:

```text
ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:<git-sha>
```

Reject releases using:

- `latest`
- `replace-with-git-sha`
- Untagged images
- Images built from unknown commits

## Dry-Run Checklist

Run server-side dry-run:

```bash
./scripts/deploy.sh \
  --image "$IMAGE" \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --container web \
  --timeout 120s \
  --dry-run
```

Confirm:

- [ ] Namespace manifest validates.
- [ ] Deployment manifest validates.
- [ ] Service manifest validates.
- [ ] No resources are changed.
- [ ] Script exits with status `0`.

If dry-run fails, stop the release and use `docs/deployment-troubleshooting.md`.

## Deployment Checklist

Run deployment:

```bash
./scripts/deploy.sh \
  --image "$IMAGE" \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --container web \
  --timeout 120s
```

Confirm:

- [ ] Script validates image tag safety.
- [ ] Kubernetes manifests apply successfully.
- [ ] Deployment image is updated.
- [ ] Rollout status completes before timeout.
- [ ] Deployment, pod, and service state are printed.

Do not start another deployment for the same workload while rollout is in progress.

## Post-Deployment Verification

Run:

```bash
kubectl -n cicd-demo rollout status deployment/cicd-kubernetes-pipeline --timeout=120s
kubectl -n cicd-demo get deployment cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get svc cicd-kubernetes-pipeline
kubectl -n cicd-demo get events --sort-by=.lastTimestamp
```

Confirm:

- [ ] Desired replicas are available.
- [ ] Pods are ready.
- [ ] No new pods are crash looping.
- [ ] No image pull failures are present.
- [ ] Service exists and points to ready endpoints.
- [ ] No critical warning events explain hidden instability.

Verify the health endpoint:

```bash
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -fsS http://127.0.0.1:8080/healthz
```

Confirm:

- [ ] `/healthz` returns `ok`.
- [ ] The release owner records verification evidence.

## Rollback Decision Checklist

Consider rollback when:

- [ ] Rollout status fails or times out.
- [ ] Pods fail readiness or liveness checks.
- [ ] `/healthz` fails after rollout.
- [ ] Error rate, latency, or service impact begins after the release.
- [ ] The failed image is associated with a clear bad change.
- [ ] Previous revision is known-good or safer than current state.

Do not roll back automatically when evidence points to:

- Cluster capacity shortage.
- Node failure.
- Registry outage.
- External dependency outage.
- Shared secret or config failure outside the deployment revision.

Rollback command:

```bash
./scripts/rollback.sh \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --timeout 120s
```

After rollback:

- [ ] Rollout status completes.
- [ ] Pods are ready.
- [ ] `/healthz` succeeds.
- [ ] Restored revision or image is recorded.

## Evidence Record

Record this after every release:

| Field | Value |
| --- | --- |
| Release owner |  |
| Git SHA |  |
| Image |  |
| Namespace |  |
| Kubernetes context |  |
| Deployment time |  |
| Dry-run result |  |
| Rollout result |  |
| Health check result |  |
| Rollback needed |  |
| Follow-up owner |  |

Example:

```text
Release owner: mahesh
Git SHA: 1a2b3c4
Image: ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:1a2b3c4
Namespace: cicd-demo
Result: rollout succeeded, /healthz returned ok
Rollback: not required
Follow-up: none
```

## Post-Release Follow-Up

After a successful release:

- [ ] Record image and Git SHA.
- [ ] Keep deployment logs with release evidence.
- [ ] Confirm no warning events remain unexplained.
- [ ] Update documentation if an operator had to discover a missing step.

After a failed release:

- [ ] Preserve failed pod logs.
- [ ] Preserve Kubernetes events.
- [ ] Record failed image tag.
- [ ] Record rollback revision if rollback was used.
- [ ] Identify the missing validation that allowed the issue through.
- [ ] Add a test, manifest check, workflow check, or runbook update.

The release is complete only when verification evidence and follow-up ownership are recorded.

Use `docs/production-readiness-review.md` for the broader review of pipeline controls, operational risks, production hardening backlog, and final portfolio signal.
