## `dependabot-docker_compose`

Docker Compose support for [`dependabot-core`][core-repo].

**Note:** This ecosystem is located in `docker/docker_compose/` to share code with the `docker` ecosystem while maintaining separate package management.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell docker_compose
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd docker_compose && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Supported tag schemas

Dependabot supports updates for Docker Compose tags that use semver versioning, dates, and build numbers.
Docker Compose uses the same tag parsing logic as the Docker ecosystem. See the [Docker README](../README.md) for details on supported tag schemas.
