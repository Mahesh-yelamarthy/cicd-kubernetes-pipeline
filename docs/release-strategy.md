# Release Strategy

This document defines the release controls planned for the CI/CD Kubernetes Pipeline.

## Release Goals

A production release should be:

- Repeatable
- Traceable
- Reviewable
- Verifiable
- Reversible

A successful CI run is necessary, but it is not sufficient to declare a production release successful. The deployed workload must also complete its rollout and pass health verification.

## Environments

The planned environment progression is:

```text
pull request validation
        |
        v
development or staging
        |
        v
production approval
        |
        v
production deployment
```

The initial implementation may use one Kubernetes target, but workflow and documentation structure should preserve the separation between validation and production deployment.

## Branch Strategy

Recommended baseline:

- Feature branches contain isolated changes.
- Pull requests trigger validation.
- `main` represents releasable code.
- Production deployments run from protected `main` commits or explicit version tags.

Direct production deployment from unreviewed feature branches should not be permitted.

## Artifact Strategy

The container image is the release artifact.

Each production image should be:

- Built by automation
- Tagged with the Git commit SHA
- Stored in a controlled registry
- Scanned when security tooling is available
- Promoted between environments without rebuilding

Rebuilding separately for each environment can create different artifacts from the same source revision. Promotion of the same immutable image reduces that risk.

## Versioning

The baseline image tag will be the Git commit SHA:

```text
application:<git-sha>
```

Optional release aliases may include:

```text
application:v1.2.0
```

Production manifests should not use mutable tags such as `latest`.

## Deployment Strategy

The initial strategy will use Kubernetes rolling updates.

Rolling updates provide:

- Controlled replacement of old pods
- Readiness-based traffic eligibility
- Native rollout status
- Native revision history
- Straightforward rollback

Future manifests should define:

- Readiness probes
- Liveness probes
- Resource requests and limits
- Rolling update parameters
- Replica count
- Revision history limit

The baseline manifests now define these controls for the demo workload. Deployment automation should update only the image tag and then verify the rollout before recording the release.

## Release Gates

Before deployment:

- Required CI checks pass.
- The image exists in the registry.
- The image tag matches the intended commit.
- Kubernetes manifests pass validation.
- Required secrets and environment configuration exist.
- The target environment is explicit.

After deployment:

- Kubernetes rollout completes within the timeout.
- Desired replicas are available.
- Pods are ready.
- The application health check succeeds.
- No critical deployment events are present.

## Rollback Policy

Rollback should be initiated when:

- The rollout exceeds its timeout.
- New pods repeatedly fail readiness.
- The application health endpoint fails.
- Error rate or latency increases materially after release.
- A critical functional regression is confirmed.

The rollback target should be the most recent known-good Kubernetes revision or immutable image.

The current rollback automation is:

```text
scripts/rollback.sh
```

Use it to read rollout history, roll back to the previous or specified revision, and verify rollout status:

```bash
./scripts/rollback.sh \
  --namespace cicd-demo \
  --deployment cicd-kubernetes-pipeline \
  --timeout 120s
```

Rollback does not replace incident analysis. After service is restored, the team should document:

- Trigger
- Impact
- Failed version
- Restored version
- Detection method
- Corrective action

## Production Approval

The future deployment workflow should use GitHub Environments for production.

Recommended controls:

- Required reviewer
- Restricted deployment branches
- Environment-scoped secrets
- Deployment history

This creates a visible approval boundary without embedding manual credentials in scripts.

## Release Ownership

| Role | Responsibility |
| --- | --- |
| Developer | Provides tested application changes and release context. |
| Reviewer | Reviews code, workflow, manifest, and operational risk. |
| Pipeline | Builds, validates, deploys, and records execution results. |
| Release owner | Confirms readiness, monitors rollout, and coordinates rollback if needed. |
| Service owner | Verifies application behavior and owns post-release issues. |

## Current Scope

This version establishes release policy, deployment automation expectations, and rollback automation expectations.

Future commits will implement the deployment workflow, release checklist, and production deployment guide.
