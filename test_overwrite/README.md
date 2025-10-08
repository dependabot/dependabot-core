## `dependabot-test_overwrite`

TestOverwrite support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell test_overwrite
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd test_overwrite && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Implementation Status

This ecosystem is currently under development. See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for implementation guidelines.

#### Required Classes
- [ ] FileFetcher
- [ ] FileParser
- [ ] UpdateChecker
- [ ] FileUpdater

#### Optional Classes
- [ ] MetadataFinder
- [ ] Version
- [ ] Requirement

#### Supporting Infrastructure
- [ ] Comprehensive unit tests
- [ ] CI/CD integration
- [ ] Documentation
