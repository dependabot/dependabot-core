## `dependabot-bun`

Bun support for [`dependabot-core`][core-repo].

Transitive update resolution follows the original lockfile entries for the
installed version being updated, so unrelated installed versions are not
reported as the result of the update.
Checks follow the original consumers through ancestor resolutions when Bun hoists
or deduplicates a package, and retain the vulnerable version if no replacement can
be verified.
Verification uses installed alias names and includes optional and peer consumers.
Dependency metadata is read from the appropriate registry or non-registry tuple
layout, including Git consumers of registry packages.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell bun
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd bun && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
