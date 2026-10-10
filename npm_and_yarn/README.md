## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### npm cooldown resolution

On npm 11.10 and later, transitive version resolution and lockfile updates use
the same release-age policy. Ordinary updates retain stricter `.npmrc` gates;
security updates bypass release-age gates.
Duplicate `.npmrc` keys use npm's last-setting-wins semantics in both version
selection and native commands.

When semver cooldown windows differ, resolution checks the version actually
allowed by parent constraints and repeats from the original lockfile only if
that version needs a different gate. If gates cycle, no resolvable update is
reported: npm's global gate cannot reproduce that candidate when writing it.

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
