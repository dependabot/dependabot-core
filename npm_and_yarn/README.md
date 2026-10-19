## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### Transitive dependency conflicts

Conflict detection checks requirements resolving to the installed version being
updated, so unrelated installed versions do not block a compatible update.
Exact pins and incompatible requirements on the targeted version remain blockers.

Yarn Berry security updates use temporary descriptor-specific resolutions to
update the vulnerable version within its existing requirements, preserving the
manifest and unrelated lockfile resolutions.
Temporary rules take precedence over existing broad resolutions; the original
manifest is restored before the final install.
Descriptor matching uses the real package name rather than aliases installing
other packages. Lockfiles without the targeted installed version are left
unchanged, without unscoped updates or audit-fix fallback.

Security PR refreshes select the vulnerable installed version, just like creation.
npm security resolution checks track the original nodes in the updated lockfile instead
of reporting an unrelated lower or higher installed version.
Checks follow the original consumers through ancestor resolutions when npm hoists
or deduplicates a package, and retain the vulnerable version if no replacement can
be verified.
Incoming consumers are indexed once per lockfile, rather than rescanned for every
installed copy of the targeted version.

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
