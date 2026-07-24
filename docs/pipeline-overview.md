# Pipeline Overview

This document defines the delivery flow for the CI/CD Kubernetes Pipeline. It provides the architectural baseline for build, validation, deployment, and rollback automation.

## Objectives

The pipeline should provide a controlled path from source code to a running Kubernetes workload.

Primary objectives:

1. Validate changes before producing a release artifact.
2. Build a reproducible container image.
3. Associate the image with a source commit.
4. Deploy through version-controlled Kubernetes configuration.
5. Verify rollout health.
6. Provide a clear rollback path when deployment fails.

## Delivery Flow

### 1. Source Change

A developer pushes a branch or opens a pull request.

The continuous integration workflow should validate:

- Repository configuration
- Application tests when available
- Docker build correctness
- Kubernetes manifest syntax
- Required files and metadata

The current CI workflow validates required container files, builds the Docker image, inspects image metadata, and uploads a short-retention image artifact for traceability.

### 2. Build

After validation succeeds, the pipeline builds a container image from the repository's `Dockerfile`.

The build should:

- Use a deterministic base image reference where practical
- Minimize unnecessary build context
- Run as a non-root user when the application permits
- Exclude development files with `.dockerignore`
- Produce clear build logs

The current build foundation uses a non-root NGINX runtime on port `8080`, a small static application, and a `/healthz` endpoint that future Kubernetes probes and deployment checks can reuse.

### 3. Tag

Images should use immutable, traceable tags.

Recommended tag:

```text
<registry>/<application>:<git-sha>
```

Human-readable release tags such as semantic versions may also point to the same immutable image.

Avoid relying on `latest` for production deployments because it does not identify the exact artifact being deployed.

### 4. Publish

The image is pushed to an authenticated container registry.

Registry credentials should be provided through GitHub Actions secrets or workload identity. Credentials must not be stored in workflow files.

### 5. Deploy

The deployment workflow updates or applies the Kubernetes manifests under `k8s/`.

Expected deployment controls:

- Explicit target environment
- Explicit image tag
- Least-privilege cluster credentials
- Deployment timeout
- Clear command output
- Serialized production deployments where required

The current manifest set includes a namespace, deployment, and service. The deployment uses rolling updates, readiness and liveness probes, resource requests and limits, and an immutable image placeholder that `scripts/deploy.sh` replaces with a Git SHA tag.

### 6. Verify

The pipeline should not consider a deployment successful immediately after `kubectl apply`.

Verification should include:

```bash
kubectl rollout status deployment/<name> --timeout=120s
```

Additional checks may include:

- Desired and available replica comparison
- Pod readiness
- Service endpoint availability
- Application health endpoint
- Recent Kubernetes events

The current deployment script waits for rollout status and prints deployment, pod, and service state after the image update.

### 7. Record

Successful releases should be traceable through:

- Git commit SHA
- Container image tag
- GitHub Actions run
- Deployment timestamp
- Target environment

### 8. Roll Back

If rollout verification fails, the workflow should stop and provide clear rollback instructions.

Rollback automation supports:

```bash
./scripts/rollback.sh --namespace cicd-demo --deployment cicd-kubernetes-pipeline
```

Rollback success must also be verified with `kubectl rollout status`.

## Workflow Separation

The project will separate continuous integration from deployment.

| Workflow | Trigger | Responsibility |
| --- | --- | --- |
| Build workflow | Pull request and branch push | Validate configuration and build the container image. |
| Deployment script | Manual operator run or future protected workflow | Deploy a known image to Kubernetes and verify the rollout. |

This separation reduces the risk that every code validation event can change a runtime environment.

## Security Boundaries

The pipeline should follow these controls:

- Use GitHub environment protection for production.
- Limit workflow token permissions.
- Pin third-party GitHub Actions to stable versions or commit SHAs.
- Store secrets outside the repository.
- Use short-lived cluster credentials where supported.
- Avoid printing secrets in command output.
- Restrict production deployment triggers.

## Failure Behavior

Pipeline failures should be explicit and actionable.

Examples:

| Failure | Expected Behavior |
| --- | --- |
| Test or validation failure | Stop before image publication. |
| Container build failure | Preserve build logs and stop deployment. |
| Registry authentication failure | Stop without modifying Kubernetes. |
| Manifest application failure | Report the failed command and cluster response. |
| Rollout timeout | Collect deployment, pod, and event context; initiate or recommend rollback. |
| Health check failure | Mark the release failed even if Kubernetes reports available replicas. |

## Future Implementation

Planned additions:

- `.github/workflows/deploy.yml`
- Deployment workflow runbooks
- Production troubleshooting guides
