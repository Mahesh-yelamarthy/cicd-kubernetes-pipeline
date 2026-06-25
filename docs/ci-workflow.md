# CI Build Workflow

This document explains the initial GitHub Actions workflow in `.github/workflows/build.yml`.

## Purpose

The workflow validates that the repository can produce a container image from source control. It does not deploy to Kubernetes and does not publish to a registry yet.

This separation keeps the first CI implementation focused on build correctness before release automation is added.

## Triggers

The workflow runs on:

- Pull requests targeting `main`
- Pushes to `main`
- Manual `workflow_dispatch`

Pull request runs give reviewers confidence that Docker and required runtime files still build before a change is merged.

## Validation Steps

The workflow performs these steps:

1. Checks out the repository.
2. Derives an immutable image tag from the Git commit SHA.
3. Confirms required files exist.
4. Builds the Docker image.
5. Inspects image metadata and layer history.
6. Exports the image to a short-retention workflow artifact.

## Artifact Strategy

The image artifact is saved as:

```text
build/cicd-kubernetes-pipeline-<short-sha>.tar
```

Artifact retention is intentionally short. The workflow artifact is for validation and review only. A later release workflow should publish immutable images to a real container registry.

## Security Controls

The workflow uses:

- `contents: read` permissions only
- Concurrency cancellation per Git ref
- No repository secrets
- No deployment credentials
- No registry push step

These controls reduce blast radius while the project is still in the build-validation stage.

## Failure Behavior

| Failure | Expected Result |
| --- | --- |
| Required file missing | Stop before Docker build. |
| Docker build failure | Stop before image export. |
| Image export failure | Fail the workflow and preserve build logs. |
| Artifact upload failure | Fail the workflow because the validation artifact is missing. |

## Future Expansion

Future workflow commits should add:

- Dockerfile linting
- Container vulnerability scanning
- Registry authentication through GitHub secrets or OIDC
- Immutable image publication
- Kubernetes manifest validation
- Deployment workflow separation with environment protection
