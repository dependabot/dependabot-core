## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### Native npm transitive updates

`npm update` accepts package names, not per-package version constraints. Dependabot
checks every changed lockfile occurrence before accepting a transitive update,
including nested packages and aliases. The resolver rejects versions above its
allowable version or inside an ignore range; the writer raises `UpdateNotPossible`
if npm exceeds the requested version. Existing unchanged occurrences are preserved.

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

[core-repo]: https://github.com/dependabot/dependabot-core
