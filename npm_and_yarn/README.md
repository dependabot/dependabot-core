## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### npm lockfile identities

Workspace records in modern npm lockfiles describe local projects, not registry dependencies. Packages installed beneath a workspace's `node_modules` directory remain update candidates.

For npm v3 lockfiles, version updates retain alias installation names and their independent versions, while registry and metadata requests use the actual package name. Native npm updates therefore preserve alias constraints instead of merging aliases with an ordinary installation of the same package.

This does not enable rewriting alias requirements in `package.json` or matching canonical security advisories to alias installation names. Dependency graph parsing continues to use canonical package identities.

Native npm's update selection is unchanged: a workspace-only alias that native npm leaves untouched remains unchanged.

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
