## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### npm lockfile identities

Workspace records in modern npm lockfiles describe local projects, not registry dependencies. Packages installed beneath a workspace's `node_modules` directory remain update candidates.

For npm v3 lockfiles, version updates retain the installation name and carry the canonical npm package name separately. Registry and metadata requests use the canonical name; native commands use the installation name.

`all_versions` contains only versions of the selected canonical package, so unrelated alias versions do not affect its vulnerability checks. When different packages share an installation name, `npm_package_versions` retains every installed record for target-aware resolution and installation-name version blocking.

This does not enable rewriting alias requirements in `package.json` or matching canonical security advisories to alias installation names. The updater still schedules by installation name, not independently for every canonical target sharing that name. Dependency graph parsing continues to use canonical package identities.

Native npm's update selection is unchanged. This does not add canonical-target isolation between workspaces or force updates that npm leaves untouched.

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
