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
`command-name`, an optional `package-manager-version`, and the configured registry `host`. Command
arguments, credentials, full registry URLs, and subprocess output are not included.
The original exception and its fingerprint are preserved.

Error reporting does not run additional commands or fetch registry metadata.
The version is included only when the failed command's Corepack selector already
specifies a complete version; bare executables and major-only selectors omit it.
The registry host comes from existing configuration, falling back to the public
npm registry when none is configured. It does not necessarily identify the
registry involved in the failure, particularly for scoped packages.
Registry lookup type and YAML parsing failures are logged by exception class
without replacing the original command error.

[core-repo]: https://github.com/dependabot/dependabot-core
