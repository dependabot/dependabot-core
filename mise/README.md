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

### Loose pins

A loose pin such as `node = "24"` keeps its precision: Dependabot updates it to `"26"`, not
`"26.13.1"`, and proposes no update while the newest release still matches the pin. The pin
stays loose only when mise resolves it to the version Dependabot selected; when ignore rules
or cooldown hold back newer matching releases, it's pinned to the selected version exactly.

### Build variants

An exact pin with a build suffix, such as `elixir = "1.20.4-otp-29"`, only updates to versions
that also have one, so it never drops to the plain `1.20.5` build. The newest allowed version
with a build suffix wins, such as `1.20.5-otp-29` or `1.20.5-otp-30`. An exact pin without a
suffix doesn't gain one. Fuzzy and loose pins such as `"latest"` or `"1.20"` leave build
selection to mise.

The suffix number isn't matched to other tools: moving to a newer OTP build doesn't update
Erlang, so group the two tools if they should change together.

### Lockfiles

When a manifest has a [`mise.lock`](https://mise.jdx.dev/dev-tools/mise-lock.html) (or
`mise.<env>.lock`, `mise.local.lock`), Dependabot runs `mise lock <tool>` after updating the
manifest, so the lockfile records the new version for the platforms it already lists. Manifests
that share a lockfile, such as `conf.d` fragments, are loaded together. For backends that keep
dependency graphs in sidecar directories, such as `npm:` tools, the directories the
lockfile records are updated too: the new version's files are added and the old ones removed.
Loose pins such as `node = "20"` are compared against the version the lockfile records.

With a lockfile, pins the newest release still matches, such as `"latest"`, `"lts"` or `"24"`,
get lockfile-only updates: the manifest stays as it is and `mise lock --bump` moves the locked
version, but only when ignore rules and cooldown allow the version mise resolves the pin to.
Without a lockfile these pins aren't updated, because mise picks the version at install time.
After relocking, Dependabot checks that each manifest resolves to the version it selected. With
`versioning-strategy: lockfile-only`, manifests are never changed and only these updates are made.

### Limitations

- Manifests with templates in `[tools]`, such as `node = "{{ env.NODE_VERSION }}"`, are skipped.
  Dependabot runs mise in [safe mode](https://mise.jdx.dev/security.html), which restricts
  template functions, and it can't rewrite templated values. Other manifests are still updated,
  except those sharing a lockfile with a templated manifest, because mise has to load them
  together to relock.
- Tools provided by plugins (`asdf:` and `vfox:` backends, such as `op`) aren't updated: safe mode
  doesn't install or run plugins, so mise can't list their versions.
- Lockfiles are never created, only updated.
- `mise lock --bump` moves every request for a tool in a lockfile at once. When manifests sharing
  a lockfile declare the same tool, a lockfile-only update is skipped if it would also move
  another of those requests to an ignored version or one still in cooldown.
- Monorepo-root lockfiles aren't supported.

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
