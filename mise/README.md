## `dependabot-mise`

Mise support for [`dependabot-core`][core-repo].

### Supported manifests

Dependabot reads the following TOML configuration files relative to the configured directory:

- `mise.toml`, `.mise.toml`, and `.config/mise.toml`
- `mise/config.toml`, `.mise/config.toml`, and `.config/mise/config.toml`
- `.config/mise/mise.toml` and `.config/mise/mise.local.toml`
- TOML fragments directly inside `mise/conf.d/`, `.mise/conf.d/`, and `.config/mise/conf.d/`
- `mise.toml` inside folders in those `conf.d` directories, such as `mise/conf.d/node/mise.toml`

The first two groups and `conf.d` folders also support environment and local variants, such as
`mise.production.local.toml`, `.mise/config.dev.toml`, and `mise/conf.d/node/mise.dev.toml`.
Hidden fragment files and folders are ignored.
See [mise's configuration file locations](https://mise.jdx.dev/configuration.html#config-file-locations).

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell mise
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd mise && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core
