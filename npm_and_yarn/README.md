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
`command-name`, an optional `selected-package-manager-version`, and an optional list of
`configured-registry-hosts`. Command arguments, registry scopes, credentials,
full registry URLs, and subprocess output are not included. The original exception
and its fingerprint are preserved.

The selected version is included only when the failed command's Corepack selector already
specifies a complete version; bare executables and major-only selectors omit it.
This is the selected version, not confirmation of the version that ran: Corepack
can fail before launching the manager, and Yarn's `yarnPath` can delegate to another
binary. No observed version is inferred from the selector or an earlier version
check, which may have used a different executable or configuration.
The host list contains known registry configurations, including scoped registries
and credential-provided registries, but is not necessarily exhaustive and does
not identify which registry failed. No single failing host is inferred from a
subprocess error. Yarn Berry configuration is read from `.yarnrc.yml`, not
`.npmrc`; unknown Yarn versions omit registry configuration.
Registry lookup type and YAML parsing failures are logged by exception class
without replacing the original command error.

After a failure, best-effort probes run `--version` and `config get registry`
(or `config get npmRegistryServer` for Yarn Berry) with the original launcher,
working directory and environment, except that Corepack network downloads and
download prompts are disabled. They share a 10-second monotonic wall-clock budget;
continuous output does not extend it. Probe process groups are killed and their
direct children reaped on completion, failure, output overflow or timeout.
Each probe captures at most 64 KiB of stdout; stderr and raw output are not logged
or attached. Failures are logged without their potentially sensitive messages.
Successful commands and failed version checks do not trigger probes.

`post-failure-package-manager-version` reports the version observed after failure,
not proof of the version that ran in the failed process.
`post-failure-global-registry-hosts` contains only sanitized global registry hosts
reported by the probe, not scoped registries or the actual failed-request host.
The existing `configured-registry-hosts` candidates remain separate. Missing,
malformed or unsuccessful probe results are omitted without changing the original error.

[core-repo]: https://github.com/dependabot/dependabot-core
