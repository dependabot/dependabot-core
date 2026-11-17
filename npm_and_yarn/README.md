## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell npm_and_yarn
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd npm_and_yarn && rspec
   ```

### Subprocess error diagnostics

Failed npm, pnpm, and Yarn commands attach debug-only error context: an allowlisted
`command-name`, an optional `package-manager-version`, and an optional list of
`configured-registry-hosts`. Command arguments, registry scopes, credentials,
full registry URLs, and subprocess output are not included. The original exception
and its fingerprint are preserved.

Error reporting does not run additional commands or fetch registry metadata.
The version is included only when the failed command's Corepack selector already
specifies a complete version; bare executables and major-only selectors omit it.
The host list contains known registry configurations, including scoped registries
and credential-provided registries, but is not necessarily exhaustive and does
not identify which registry failed. No single failing host is inferred from a
subprocess error. Yarn Berry configuration is read from `.yarnrc.yml`, not
`.npmrc`; unknown Yarn versions omit registry configuration.
Registry lookup type and YAML parsing failures are logged by exception class
without replacing the original command error.

[core-repo]: https://github.com/dependabot/dependabot-core
