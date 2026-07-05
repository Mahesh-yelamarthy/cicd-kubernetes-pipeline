# Kubernetes Manifests

This document describes the initial Kubernetes manifests for the CI/CD Kubernetes Pipeline.

## Files

| File | Purpose |
| --- | --- |
| `k8s/namespace.yaml` | Creates the `cicd-demo` namespace for the demo workload. |
| `k8s/deployment.yaml` | Runs the web container with rolling update controls, probes, resources, and security settings. |
| `k8s/service.yaml` | Exposes the deployment through an internal ClusterIP service. |

## Deployment Model

The deployment uses:

- Two replicas for basic availability
- Rolling updates with `maxUnavailable: 0`
- Readiness and liveness probes on `/healthz`
- CPU and memory requests and limits
- Non-root pod security defaults
- Prometheus scrape annotations for the health endpoint
- A placeholder immutable image tag

The image value is intentionally not `latest`:

```text
ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:replace-with-git-sha
```

A future deployment workflow should replace this value with the Git SHA image produced by CI.

## Apply Order

Apply the namespace first, then workload resources:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

## Image Update Example

For manual validation, replace the image tag with a real immutable tag:

```bash
kubectl -n cicd-demo set image deployment/cicd-kubernetes-pipeline \
  web=ghcr.io/mahesh-yelamarthy/cicd-kubernetes-pipeline:<git-sha>
```

## Rollout Verification

After applying or updating the deployment:

```bash
kubectl -n cicd-demo rollout status deployment/cicd-kubernetes-pipeline --timeout=120s
kubectl -n cicd-demo get pods -l app.kubernetes.io/name=cicd-kubernetes-pipeline -o wide
kubectl -n cicd-demo get svc cicd-kubernetes-pipeline
```

The release should not be considered successful until rollout status completes and pods are ready.

## Local Service Check

For local testing:

```bash
kubectl -n cicd-demo port-forward svc/cicd-kubernetes-pipeline 8080:80
curl -fsS http://127.0.0.1:8080/healthz
```

Expected response:

```text
ok
```

## Production Notes

Before using these manifests in production:

- Replace the image placeholder with an immutable image tag.
- Confirm the namespace strategy matches the target cluster.
- Add image pull secrets if the registry is private.
- Add Ingress or Gateway resources when external access is required.
- Confirm resource requests and limits match observed workload behavior.
- Add PodDisruptionBudget when the workload requires maintenance availability.
- Validate manifests in CI before deployment.
