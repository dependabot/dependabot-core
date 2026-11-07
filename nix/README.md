## `dependabot-nix`

Nix support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```sh
  bin/docker-dev-shell nix
  ```

1. Run tests

  ```sh
  [dependabot-core-dev] ~ $ cd nix && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Implementation Status

This ecosystem is currently under development. See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for implementation guidelines.

#### Required Classes

- [x] FileFetcher
- [x] FileParser
- [x] UpdateChecker
- [x] FileUpdater

#### Optional Classes

- [x] MetadataFinder
- [x] Version
- [x] Requirement

#### Supporting Infrastructure

- [x] Comprehensive unit tests
- [x] CI/CD integration
- [x] Documentation
