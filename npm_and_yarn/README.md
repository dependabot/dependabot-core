## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### Native npm transitive updates

`npm update` accepts package names, not per-package version constraints. Dependabot
checks changed installations in v1, v2, and v3 lockfiles, including nested packages
and aliases. It also checks the effective replacement of a removed installation,
so deduplication cannot bypass the policy. Required installations must retain
their package identity and a valid version.

The resolver rejects versions above its allowable version or inside an ignore
range; the writer raises `UpdateNotPossible` if npm exceeds the requested version.
Existing unchanged effective versions are preserved.

An out-of-policy native result is rejected, not relabelled as a lower version.
Dependabot does not add manifest overrides to force an older candidate, since
overrides replace the parent package's requirements. Selecting an older compatible
candidate requires native npm support for per-package constraints.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell npm_and_yarn
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd npm_and_yarn && rspec
   ```

The npm spec helper clears the active npm version selector and per-directory
registrations after each example. Configure required selectors within each
example so randomized runs remain independent.

[core-repo]: https://github.com/dependabot/dependabot-core
