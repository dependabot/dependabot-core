## `dependabot-luarocks`

Luarocks support for [`dependabot-core`][core-repo].

> Note: LuaRocks lockfiles (`luarocks.lock`) are not supported yet. Only
> `.rockspec` manifests are fetched and updated.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell luarocks
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd luarocks && rspec
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
- [ ] MetadataFinder
- [x] Version
- [x] Requirement

#### Supporting Infrastructure
- [ ] Comprehensive unit tests
- [ ] CI/CD integration
- [ ] Documentation
