# `dependabot-docker`

Docker support for [`dependabot-core`][core-repo].

## Supported file types

Dependabot supports updating container image references in the following file types:

- **Dockerfiles** - Container image references in `FROM` instructions
- **Kubernetes YAML files** - Container image references in `image` fields
- **Helm values files** - Container image references in image configuration
- **Environment files (.env)** - Container image references in environment variables

### Dockerfiles

Dependabot can update container image references in `FROM` instructions within Dockerfiles. This includes both single-stage and multi-stage builds.

**Supported Dockerfile patterns:**

- `Dockerfile`
- `Dockerfile.*` (e.g., `Dockerfile.prod`, `Dockerfile.dev`)
- `*.Dockerfile`
- Custom named Dockerfiles

**Example Dockerfile:**

```dockerfile
# Base image with tag
FROM node:16.14.0 AS build

# Image with digest
FROM nginx:1.21.0@sha256:0b01b93c3a93e747fba8d9bb1025011bf108d77c9cf8252f17a6f3d63a1b5804

# Multi-stage build
FROM alpine:3.15 AS base
FROM base AS final

# Private registry image
FROM registry.company.com/base:latest
```

Dependabot will detect and update:

- Container images in `FROM` instructions
- Images with tags (e.g., `node:16.14.0`)
- Images with digests (e.g., `image@sha256:abc123...`)
- Images with both tags and digests
- Images from private registries
- Multi-stage build references

### Kubernetes YAML files

Dependabot can update container image references in Kubernetes manifest files, including Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, and Pods.

**Supported Kubernetes file patterns:**

- `*.yaml`
- `*.yml`
- Files in common Kubernetes directories (`k8s/`, `kubernetes/`, `manifests/`)

**Example Kubernetes Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  template:
    spec:
      containers:
      - name: web
        image: nginx:1.21.0@sha256:0b01b93c3a93e747fba8d9bb1025011bf108d77c9cf8252f17a6f3d63a1b5804
      - name: sidecar
        image: redis:6.2.5
      initContainers:
      - name: init
        image: busybox:1.35.0
```

**Example Kubernetes CronJob:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-job
spec:
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:13.4@sha256:abc123def456
```

Dependabot will detect and update:

- Container images in `containers` fields
- Container images in `initContainers` fields
- Images in any Kubernetes workload type
- Images with tags and/or digests
- Images from private registries

### Helm values files

Dependabot can update container image references defined in Helm values files (`values.yaml`, `values.yml`) and their variants.

**Supported Helm values file patterns:**

- `values.yaml`
- `values.yml`
- `values-*.yaml` (e.g., `values-prod.yaml`, `values-dev.yaml`)
- `*-values.yaml`

**Example values.yaml:**

```yaml
# Simple image configuration
image:
  repository: nginx
  tag: "1.21.0"
  digest: "sha256:0b01b93c3a93e747fba8d9bb1025011bf108d77c9cf8252f17a6f3d63a1b5804"

# Multiple images
images:
  web:
    repository: nginx
    tag: "1.21.0"
  cache:
    repository: redis
    tag: "6.2.5"

# Nested image configuration
services:
  frontend:
    image:
      repository: "registry.company.com/frontend"
      tag: "v2.1.0"
  backend:
    image:
      repository: "node"
      tag: "16.14.0"

# Full image reference
global:
  image: "postgres:13.4@sha256:abc123def456"
```

Dependabot will detect and update:

- Images defined with separate `repository` and `tag` fields
- Images with `digest` fields
- Full image references (e.g., `image: "nginx:1.21.0"`)
- Nested image configurations
- Images from private registries
- Custom image field names and structures

### Environment files (.env)

Dependabot can update container image references defined in `.env` files used with Kubernetes Kustomize. These files typically contain environment variables with container image references including tags and digests.

**Supported .env file patterns:**

- `.env`
- `.env.local`
- `.env.production`
- `*.env`

**Example .env file:**

```env
# Container Image Tags
WEB_IMAGE_TAG=nginx:1.21.0@sha256:0b01b93c3a93e747fba8d9bb1025011bf108d77c9cf8252f17a6f3d63a1b5804
CACHE_IMAGE_TAG=redis:6.2.5@sha256:4c854aa03f6b7e9bb2b945e8e2a17f565266a103c70bb3275b57e4f81a7e92a0
API_IMAGE=node:16.14.0
DB_IMAGE=postgres:13.4@sha256:abc123def456
```

Dependabot will detect and update:

- Container images with tags (e.g., `nginx:1.21.0`)
- Container images with digests (e.g., `image@sha256:abc123...`)
- Container images with both tags and digests
- Images from private registries
- Images with namespaces

## Running locally

1. Start a development shell

   ```bash
   bin/docker-dev-shell docker
   ```

1. Run tests

   ```bash
   [dependabot-core-dev] ~ $ cd docker && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

## Supported tag schemas

Dependabot supports updates for Docker tags that use semver versioning, dates, and build numbers.
The Docker tag class is located at:
<https://github.com/dependabot/dependabot-core/blob/main/docker/lib/dependabot/docker/tag.rb>

### Semver

Dependabot will attempt to parse a semver version from a tag and will only update it to a tag with a matching prefix and suffix.

As an example, `base-12.5.1` and `base-12.5.1-golden` would be parsed as `<prefix>-<version>` and `<prefix>-<version>-<suffix>` respectively.

That means for `base-12.5.1` only another `<prefix>-<version>` tag would be a viable update, and for `base-12.5.1-golden`, only another `<prefix>-<version>-<suffix>` tag would be viable. The exception to this is if the suffix is a SHA, in which case it does not get compared and only the `<prefix-<version>` parts are considered in finding a viable tag.

### Dates

Dependabot will parse dates in the `yyyy-mm`, `yyyy-mm-dd` formats (or with `.` instead of `-`) and update tags to the latest date.

As an example, `2024-01` will get updated to `2024-02` and `2024.01.29` will get updated to `2024.03.15`.

### Build numbers

Dependabot will recognize build numbers and will update to the highest build number available.

As an example, `21-ea-32`, `22-ea-7`, and `22-ea-jdk-nanoserver-1809` are mapped to `<version>-ea-<build_num>`, `<version>-ea-<build_num>`, and `<version>-ea-jdk-nanoserver-<build_num>` respectively.
That means only "22-ea-7" will be considered as a viable update candidate for `21-ea-32`, since it's the only one that respects that format.
