# CI/CD Kubernetes Pipeline

Production-oriented CI/CD project for building, validating, releasing, and deploying containerized applications to Kubernetes.

This repository is part of a 30-day SRE / DevOps portfolio build. It will evolve incrementally from delivery architecture and release policy into container builds, GitHub Actions workflows, Kubernetes manifests, deployment automation, rollback tooling, runbooks, and production troubleshooting guidance.

## Purpose

The project demonstrates how a production engineering team can move application changes from source control to Kubernetes with repeatable controls.

The pipeline will gradually cover:

- Container image creation
- Automated build and validation workflows
- Kubernetes deployment manifests
- Deployment automation
- Rollout verification
- Rollback automation
- Release checklists
- Deployment runbooks
- Troubleshooting guides
- Delivery architecture documentation

## Current Status

Day 6 container build foundation is complete.

The repository now includes a production-oriented Dockerfile, a minimal static workload, NGINX runtime configuration, build context controls, and container build documentation. GitHub Actions workflows, Kubernetes manifests, and rollback scripts will be added in later commits.

## Planned Repository Structure

```text
cicd-kubernetes-pipeline/
├── Dockerfile
├── .dockerignore
├── README.md
├── .github/
│   └── workflows/
├── app/
│   └── index.html
├── docs/
│   ├── container-build.md
│   ├── pipeline-overview.md
│   ├── release-strategy.md
│   └── diagrams/
├── k8s/
├── nginx/
│   └── default.conf
└── scripts/
```

## Delivery Goals

The pipeline is designed to answer the following production questions:

- Did the source change pass automated validation?
- Is the container image reproducible and traceable to a commit?
- Which image version is currently deployed?
- Did the Kubernetes rollout complete successfully?
- Can the release be rolled back safely?
- Are deployment failures documented and diagnosable?

## Planned Pipeline Stages

```text
Source change
    |
    v
Static and configuration validation
    |
    v
Container image build
    |
    v
Image tagging and publication
    |
    v
Kubernetes deployment
    |
    v
Rollout and health verification
    |
    +--> Success: record release
    |
    +--> Failure: stop and roll back
```

## Engineering Principles

- Every deployed artifact should be traceable to source control.
- Builds should be repeatable and automated.
- Deployment workflows should fail clearly and stop on errors.
- Kubernetes rollouts should be verified before a release is considered complete.
- Rollback procedures should be documented and tested.
- Credentials should be stored in GitHub or Kubernetes secret stores, never committed.
- Production releases should use immutable image tags.
- Pipeline configuration should be reviewed like application code.

## Planned Tooling

| Area | Tool |
| --- | --- |
| Source control | GitHub |
| CI/CD orchestration | GitHub Actions |
| Container build | Docker |
| Runtime platform | Kubernetes |
| Deployment control | `kubectl` |
| Configuration format | YAML |
| Operational automation | Bash |

## Documentation

- [Container build](docs/container-build.md)
- [Pipeline overview](docs/pipeline-overview.md)
- [Release strategy](docs/release-strategy.md)

## Recruiter Signal

This repository is designed to demonstrate:

- CI/CD architecture and workflow design
- Container delivery practices
- Kubernetes deployment knowledge
- Release and rollback discipline
- Production-oriented documentation
- Operational ownership beyond a successful build

## Day 6 Commit

```text
feat: add production-ready docker build foundation
```
