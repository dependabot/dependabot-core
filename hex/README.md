## `dependabot-hex`

Elixir support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell hex
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd hex && rspec
   ```

**Note**: Some integration tests require `HEX_PM_ORGANIZATION_TOKEN` environment variable to access private packages on Hex.pm. Tests skip gracefully if not set. See [PRIVATE_REGISTRY_SETUP.md](PRIVATE_REGISTRY_SETUP.md) for details.

[core-repo]: https://github.com/dependabot/dependabot-core
