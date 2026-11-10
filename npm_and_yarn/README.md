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
`command-name`, the `package-manager-version`, and the registry `host`. Command
arguments, credentials, full registry URLs, and subprocess output are not included.
The original exception and its fingerprint are preserved.

Version and registry probes use the same executable, working directory, and
environment as the failed command, with a ten-second timeout per probe. Unavailable
diagnostics are omitted and logged; failed version commands are not probed again.

[core-repo]: https://github.com/dependabot/dependabot-core
