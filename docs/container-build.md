# Container Build

This document defines the first container build implementation for the CI/CD Kubernetes Pipeline.

## Build Goal

The image provides a small, deterministic workload that can be used by future GitHub Actions and Kubernetes deployment steps. It is intentionally simple so pipeline behavior is easy to isolate from application complexity.

The image includes:

- A static HTML application under `app/`
- An NGINX runtime configuration under `nginx/`
- A `/healthz` endpoint for container and Kubernetes health checks
- A non-root NGINX base image that listens on port `8080`

## Build Command

Use a Git SHA or another immutable identifier for the image tag:

```bash
docker build -t cicd-kubernetes-pipeline:$(git rev-parse --short HEAD) .
```

Avoid using `latest` for release or deployment workflows because it does not identify the exact artifact being deployed.

## Local Runtime Check

Run the image locally:

```bash
docker run --rm -p 8080:8080 cicd-kubernetes-pipeline:$(git rev-parse --short HEAD)
```

In a separate terminal, verify the app and health endpoint:

```bash
curl -fsS http://127.0.0.1:8080/
curl -fsS http://127.0.0.1:8080/healthz
```

Expected health response:

```text
ok
```

## Dockerfile Controls

The Dockerfile is designed with production delivery practices in mind:

| Control | Implementation |
| --- | --- |
| Non-root runtime | Uses `nginxinc/nginx-unprivileged` and listens on port `8080`. |
| Small build context | `.dockerignore` excludes repository metadata, docs, future manifests, and transient files. |
| Traceable metadata | OCI labels identify the project and source repository. |
| Runtime health | `HEALTHCHECK` calls the local `/healthz` endpoint. |
| Clear logs | NGINX access and error logs are written to stdout and stderr. |

## Future CI Usage

The GitHub Actions build workflow should:

1. Check out the repository.
2. Validate the Dockerfile and NGINX configuration.
3. Build the image.
4. Tag the image with the Git commit SHA.
5. Preserve build evidence for review.
6. Push the image only after a future release workflow adds registry controls.
7. Pass the immutable image tag to deployment automation.

See [CI build workflow](ci-workflow.md) for the current workflow behavior.

## Kubernetes Readiness

Future Kubernetes manifests should use the same health endpoint:

```yaml
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

The image should be considered deployable only when the build completes and the health endpoint responds successfully.
