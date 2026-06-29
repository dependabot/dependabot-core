## `dependabot-devbox`

Devbox support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell devbox
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd devbox && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Implementation Status

Beta implementation complete and gated behind `allow_beta_ecosystems?`. See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for implementation guidelines.

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
