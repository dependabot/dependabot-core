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

### Lockfiles

When a manifest has a [`mise.lock`](https://mise.jdx.dev/dev-tools/mise-lock.html) (or
`mise.<env>.lock`, `mise.local.lock`), Dependabot runs `mise lock <tool>` after updating the
manifest, so the lockfile records the new version for the platforms it already lists. Manifests
that share a lockfile, such as `conf.d` fragments, are loaded together. For backends that keep
dependency graphs in sidecar directories, such as `npm:` tools, the directories the
lockfile records are updated too: the new version's files are added and the old ones removed.
Loose pins such as `node = "20"` are compared against the version the lockfile records.

### Limitations

- Manifests with templates in `[tools]`, such as `node = "{{ env.NODE_VERSION }}"`, are skipped.
  Dependabot runs mise in [safe mode](https://mise.jdx.dev/security.html), which disables
  templates, and it can't rewrite templated values. Other manifests are still updated, except those
  sharing a lockfile with a templated manifest, because mise has to load them together to relock.
- Tools provided by plugins (`asdf:` and `vfox:` backends, such as `op`) aren't updated: safe mode
  doesn't install or run plugins, so mise can't list their versions.
- Lockfiles are never created, only updated.
- Loose pins such as `node = "20"` aren't advanced in the lockfile, and monorepo-root lockfiles
  aren't supported.

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
